function readInstalled(file: string): unknown {
  const marker: unknown = JSON.parse(fs.readFileSync(file, "utf8"));
  assert.ok(api.record(marker));
  return marker["installed"];
}
import api = require("./scrypted-api.cjs");
import assert = require("node:assert/strict");
import fs = require("node:fs");
import os = require("node:os");
import path = require("node:path");
import localScryptedPluginMarkerCjs = require("./scrypted-plugin-marker.cjs");
const { reconcile } = localScryptedPluginMarkerCjs;

async function main() {
  const serverRoot = process.argv[2];
  if (!serverRoot)
    throw new Error("Pass the built Scrypted server package root");
  const WrappedLevel = api.loadDatabase(serverRoot);
  const Plugin = api.loadModel(serverRoot, "Plugin");
  const volume = fs.mkdtempSync(
    path.join(os.tmpdir(), "scrypted-plugin-marker-"),
  );
  const markerFile = path.join(volume, ".nix-managed-plugins.json");
  const manifestFile = path.join(volume, "manifest.json");
  try {
    fs.writeFileSync(
      manifestFile,
      JSON.stringify([
        { name: "@scrypted/arlo", version: "1.0.0", source: "npm" },
        { name: "@scrypted/snapshot", version: "1.0.0", source: "npm" },
      ]),
    );
    const db = new WrappedLevel(path.join(volume, "scrypted.db"));
    await db.open();
    const installed = new Plugin();
    installed._id = "@scrypted/arlo";
    installed.packageJson = { name: "@scrypted/arlo", version: "1.0.0" };
    await db.upsert(installed);
    await db.close();
    fs.writeFileSync(
      markerFile,
      JSON.stringify({
        schema: 1,
        installed: {
          "@scrypted/arlo": "@scrypted/arlo@1.0.0",
          "@scrypted/snapshot": "@scrypted/snapshot@1.0.0",
        },
      }),
    );
    assert.equal(await reconcile(serverRoot, volume, manifestFile), "updated");
    assert.deepEqual(readInstalled(markerFile), {
      "@scrypted/arlo": "@scrypted/arlo@1.0.0",
    });
    assert.equal(
      await reconcile(serverRoot, volume, manifestFile),
      "unchanged",
    );
    assert.equal(fs.statSync(markerFile).mode & 0o777, 0o600);
    const changed = new WrappedLevel(path.join(volume, "scrypted.db"));
    await changed.open();
    installed.packageJson.version = "2.0.0";
    await changed.upsert(installed);
    await changed.close();
    assert.equal(await reconcile(serverRoot, volume, manifestFile), "updated");
    assert.deepEqual(readInstalled(markerFile), {});
    console.log("Scrypted plugin marker checks passed");
  } finally {
    fs.rmSync(volume, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
