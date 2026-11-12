import api = require("./scrypted-api.cjs");
import assert = require("node:assert/strict");
import fs = require("node:fs");
import os = require("node:os");
import path = require("node:path");
import localScryptedManagedSettingsCjs = require("./scrypted-managed-settings.cjs");
const {
  configuredStorage,
  disabledUpdaterState,
  reconcile,
  selectHomeKit,
  selectPluginUpdater,
} = localScryptedManagedSettingsCjs;

const provider = {
  pluginId: "@scrypted/homekit",
  storage: { pincode: "private", advertiserOverride: "ciao" },
};
const device = selectHomeKit([
  { pluginId: "@scrypted/arlo", storage: {} },
  provider,
  { pluginId: "@scrypted/homekit", nativeId: "save-video-clips", storage: {} },
]);
assert.equal(device, provider);
assert.ok(device);
assert.deepEqual(configuredStorage(device, "192.0.2.10"), {
  pincode: "private",
  advertiserOverride: "avahi",
  advertiserAddresses: "192.0.2.10",
});
assert.equal(provider.storage.advertiserOverride, "ciao");
assert.throws(() => selectHomeKit([provider, { ...provider }]), /Multiple/);
assert.throws(() => configuredStorage(provider, "127.0.0.1:443"), /Invalid/);
assert.throws(
  () => configuredStorage({ storage: null }, "192.0.2.10"),
  /Invalid/,
);
const updater = {
  pluginId: "@scrypted/core",
  nativeId: "automation:update-plugins",
  state: { on: { value: true }, name: { value: "Autoupdate Plugins" } },
};
assert.equal(selectPluginUpdater([provider, updater]), updater);
assert.equal(disabledUpdaterState(updater).on.value, false);
assert.equal(updater.state.on.value, true);
assert.throws(() => selectPluginUpdater([updater, { ...updater }]), /Multiple/);
assert.throws(() => disabledUpdaterState({ state: {} }), /Invalid/);

async function testDatabase(serverRoot: string) {
  const volume = fs.mkdtempSync(
    path.join(os.tmpdir(), "scrypted-homekit-settings-"),
  );
  const WrappedLevel = api.loadDatabase(serverRoot);
  const PluginDevice = api.loadModel(serverRoot, "PluginDevice");
  try {
    const db = new WrappedLevel(path.join(volume, "scrypted.db"));
    await db.open();
    const plugin = new PluginDevice("test-homekit");
    plugin.pluginId = "@scrypted/homekit";
    plugin.storage = { pincode: "private", advertiserOverride: "ciao" };
    await db.upsert(plugin);
    const automation = new PluginDevice("test-update-plugins");
    automation.pluginId = "@scrypted/core";
    automation.nativeId = "automation:update-plugins";
    automation.state = {
      on: { value: true },
      name: { value: "Autoupdate Plugins" },
    };
    automation.storage = { data: "{}" };
    await db.upsert(automation);
    await db.close();

    assert.equal(await reconcile(serverRoot, volume, "192.0.2.10"), "updated");
    assert.equal(
      await reconcile(serverRoot, volume, "192.0.2.10"),
      "unchanged",
    );

    const verified = new WrappedLevel(path.join(volume, "scrypted.db"));
    await verified.open();
    assert.ok(verified.tryGet);
    const saved = await verified.tryGet(PluginDevice, "test-homekit");
    assert.ok(api.isDevice(saved) && api.record(saved.storage));
    assert.equal(saved.storage["advertiserOverride"], "avahi");
    assert.equal(saved.storage["advertiserAddresses"], "192.0.2.10");
    assert.equal(saved.storage["pincode"], "private");
    const savedUpdater = await verified.tryGet(
      PluginDevice,
      "test-update-plugins",
    );
    assert.ok(api.isDevice(savedUpdater) && api.record(savedUpdater.storage));
    assert.equal(savedUpdater.state?.on?.value, false);
    assert.equal(savedUpdater.storage["data"], "{}");
    await verified.close();
  } finally {
    fs.rmSync(volume, { recursive: true, force: true });
  }
}

async function testPrevalidation(): Promise<void> {
  const root = fs.mkdtempSync(
    path.join(os.tmpdir(), "scrypted-prevalidation-"),
  );
  const serverRoot = path.join(root, "server");
  fs.mkdirSync(path.join(serverRoot, "dist"), { recursive: true });
  fs.writeFileSync(
    path.join(serverRoot, "dist/level.js"),
    `const writes = [];
module.exports = {
  writes,
  default: class {
    async open() {}
    async close() {}
    async *getAll() {
      yield { pluginId: '@scrypted/homekit', storage: { advertiserOverride: 'ciao' } };
      yield { pluginId: '@scrypted/core', nativeId: 'automation:update-plugins', state: {} };
    }
    async upsert(record) { writes.push(record); }
  },
};`,
  );
  fs.writeFileSync(
    path.join(serverRoot, "dist/db-types.js"),
    "module.exports = { PluginDevice: class PluginDevice {} };",
  );
  try {
    await assert.rejects(
      reconcile(serverRoot, root, "192.0.2.10"),
      /Invalid Scrypted plugin updater state/,
    );
    const levelModule: unknown = require(
      path.join(serverRoot, "dist/level.js"),
    );
    assert.ok(api.record(levelModule));
    const writes = levelModule["writes"];
    assert.deepEqual(writes, []);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

async function main(): Promise<void> {
  await testPrevalidation();
  if (process.argv[2]) await testDatabase(process.argv[2]);
}

main().catch((error: unknown) => {
  console.error(error);
  process.exitCode = 1;
});
