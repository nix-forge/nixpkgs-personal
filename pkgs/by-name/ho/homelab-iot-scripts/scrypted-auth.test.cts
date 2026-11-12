import api = require("./scrypted-api.cjs");
import assert = require("node:assert/strict");
import fs = require("node:fs");
import os = require("node:os");
import path = require("node:path");
import localScryptedAuthCjs = require("./scrypted-auth.cjs");
const { reconcile } = localScryptedAuthCjs;

const selectedRoot = process.argv[2];
if (!selectedRoot)
  throw new Error("Pass the built Scrypted server package root");
const serverRoot: string = selectedRoot;
const WrappedLevel = api.loadDatabase(serverRoot);
const ScryptedUser = api.loadModel(serverRoot, "ScryptedUser");
const Settings = api.loadModel(serverRoot, "Settings");
const { UsersService, setScryptedUserPassword } = api.loadUsers(serverRoot);

async function inspect(volume: string) {
  const db = new WrappedLevel(path.join(volume, "scrypted.db"));
  await db.open();
  try {
    const users = [];
    for await (const user of db.getAll(ScryptedUser)) {
      assert.ok(api.isUser(user));
      users.push(user);
    }
    return users;
  } finally {
    await db.close();
  }
}

async function main() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "scrypted-auth-test-"));
  const volume = path.join(temp, "volume");
  const usernameFile = path.join(temp, "username");
  const passwordFile = path.join(temp, "password");
  const firstPassword = "test-only-initial-password-12345";
  const secondPassword = "test-only-replacement-password-67890";
  fs.mkdirSync(volume);
  fs.writeFileSync(usernameFile, "test-admin\n", { mode: 0o600 });
  fs.writeFileSync(passwordFile, `${firstPassword}\n`, { mode: 0o600 });
  try {
    assert.equal(
      await reconcile(serverRoot, usernameFile, passwordFile, volume),
      "created",
    );
    let [user] = await inspect(volume);
    assert.ok(user);
    assert.ok(user);
    assert.equal(user._id, "test-admin");
    assert.equal(user.aclId, undefined);
    assert.equal(typeof user.passwordHash, "string");
    const originalToken = user.token;
    const originalHash = user.passwordHash;
    const markerFile = path.join(volume, ".nix-seal-scrypted-admin.json");
    assert.equal(fs.statSync(markerFile).mode & 0o777, 0o600);
    assert(!fs.readFileSync(markerFile, "utf8").includes(firstPassword));

    assert.equal(
      await reconcile(serverRoot, usernameFile, passwordFile, volume),
      "unchanged",
    );
    [user] = await inspect(volume);
    assert.ok(user);
    assert.equal(user.token, originalToken);

    fs.writeFileSync(passwordFile, `${secondPassword}\n`);
    assert.equal(
      await reconcile(serverRoot, usernameFile, passwordFile, volume),
      "rotated",
    );
    [user] = await inspect(volume);
    assert.ok(user);
    assert.notEqual(user.passwordHash, originalHash);
    assert.notEqual(user.token, originalToken);

    // A password changed in Scrypted itself must be restored from nix-seal.
    const changedInUiToken = user.token;
    const changedInUi = new WrappedLevel(path.join(volume, "scrypted.db"));
    await changedInUi.open();
    try {
      await setScryptedUserPassword(
        user,
        "test-only-unmanaged-password-12345",
        Date.now(),
      );
      await changedInUi.upsert(user);
    } finally {
      await changedInUi.close();
    }
    assert.notEqual(user.token, changedInUiToken);
    assert.equal(
      await reconcile(serverRoot, usernameFile, passwordFile, volume),
      "rotated",
    );
    [user] = await inspect(volume);
    assert.ok(user);
    assert.notEqual(user.token, changedInUiToken);
    assert.equal(
      await reconcile(serverRoot, usernameFile, passwordFile, volume),
      "unchanged",
    );

    // An older installation has no marker; reconcile it once without knowing
    // Scrypted's current password hash format.
    fs.unlinkSync(markerFile);
    assert.equal(
      await reconcile(serverRoot, usernameFile, passwordFile, volume),
      "rotated",
    );
    assert.equal(
      await reconcile(serverRoot, usernameFile, passwordFile, volume),
      "unchanged",
    );

    fs.writeFileSync(usernameFile, "renamed-admin\n");
    assert.equal(
      await reconcile(serverRoot, usernameFile, passwordFile, volume),
      "renamed",
    );
    [user] = await inspect(volume);
    assert.ok(user);
    assert.equal(user._id, "renamed-admin");
    assert.equal((await inspect(volume)).length, 1);
    assert.equal(
      await reconcile(serverRoot, usernameFile, passwordFile, volume),
      "unchanged",
    );

    // A marker-free account cannot be renamed on the strength of a new sealed
    // username alone; it may belong to an administrator outside this module.
    fs.unlinkSync(markerFile);
    fs.writeFileSync(usernameFile, "unverified-admin\n");
    await assert.rejects(
      reconcile(serverRoot, usernameFile, passwordFile, volume),
      /unmanaged account/,
    );
    fs.writeFileSync(usernameFile, "renamed-admin\n");
    assert.equal(
      await reconcile(serverRoot, usernameFile, passwordFile, volume),
      "rotated",
    );

    const db = new WrappedLevel(path.join(volume, "scrypted.db"));
    await db.open();
    try {
      await UsersService.addUserToDatabase(
        db,
        "unmanaged",
        "test-only-other-password-12345",
      );
      const setting = new Settings();
      setting._id = "test-setting";
      setting.value = "preserved";
      await db.upsert(setting);
    } finally {
      await db.close();
    }
    await assert.rejects(
      reconcile(serverRoot, usernameFile, passwordFile, volume),
      /unmanaged account/,
    );
    const verify = new WrappedLevel(path.join(volume, "scrypted.db"));
    await verify.open();
    try {
      assert.ok(verify.tryGet && verify.getCount);
      const settingValue = await verify.tryGet(Settings, "test-setting");
      assert.ok(api.record(settingValue));
      assert.equal(settingValue["value"], "preserved");
      assert.equal(await verify.getCount(ScryptedUser), 2);
    } finally {
      await verify.close();
    }
    console.log("Scrypted administrator reconciliation checks passed");
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
