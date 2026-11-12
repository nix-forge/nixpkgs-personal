import api = require("./scrypted-api.cjs");
// Reconcile Scrypted's sole administrator before the server opens its database.
// Use Scrypted's own user helpers for password writes; keep only a digest of
// the managed credential and user token to detect changes between starts.
import crypto = require("node:crypto");
import fs = require("node:fs");
import path = require("node:path");

interface Marker {
  schema: 1;
  credentialDigest: string;
  tokenDigest: string;
}

interface ScryptedUserRecord {
  _id: string;
  token: string;
  aclId?: string;
}

function readCredential(
  file: string,
  minLength: number,
  maxLength: number,
): string {
  const value = fs.readFileSync(file, "utf8").replace(/\n$/, "");
  if (
    value.length < minLength ||
    value.length > maxLength ||
    /[\r\n\0]/.test(value)
  )
    throw new Error("Invalid Scrypted administrator credential");
  return value;
}

function digest(value: string): string {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function readMarker(file: string): Marker | undefined {
  if (!fs.existsSync(file)) return undefined;
  const parsed: unknown = JSON.parse(fs.readFileSync(file, "utf8"));
  const credentialDigest: unknown =
    parsed && typeof parsed === "object"
      ? Reflect.get(parsed, "credentialDigest")
      : undefined;
  const tokenDigest: unknown =
    parsed && typeof parsed === "object"
      ? Reflect.get(parsed, "tokenDigest")
      : undefined;
  if (
    !parsed ||
    typeof parsed !== "object" ||
    Reflect.get(parsed, "schema") !== 1 ||
    typeof credentialDigest !== "string" ||
    !/^[a-f0-9]{64}$/.test(credentialDigest) ||
    typeof tokenDigest !== "string" ||
    !/^[a-f0-9]{64}$/.test(tokenDigest)
  )
    throw new Error("Invalid Scrypted administrator management marker");
  return { schema: 1, credentialDigest, tokenDigest };
}

function writeMarker(file: string, marker: Marker): void {
  const temporary = `${file}.${process.pid}.tmp`;
  try {
    fs.writeFileSync(temporary, `${JSON.stringify(marker)}\n`, {
      flag: "wx",
      mode: 0o600,
    });
    fs.renameSync(temporary, file);
  } finally {
    if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
  }
}

async function reconcile(
  serverRoot: string,
  usernameFile: string,
  passwordFile: string,
  volume: string,
): Promise<"created" | "unchanged" | "renamed" | "rotated"> {
  const username = readCredential(usernameFile, 1, 128);
  const password = readCredential(passwordFile, 24, 1024);
  if (fs.existsSync(path.join(volume, "reset-login")))
    throw new Error(
      "Remove the pending Scrypted reset-login marker before starting",
    );

  const WrappedLevel = api.loadDatabase(serverRoot);
  const ScryptedUser = api.loadModel(serverRoot, "ScryptedUser");
  const { UsersService, setScryptedUserPassword } = api.loadUsers(serverRoot);
  const markerFile = path.join(volume, ".nix-seal-scrypted-admin.json");
  const credentialDigest = digest(`${username}\0${password}`);
  const db = new WrappedLevel(path.join(volume, "scrypted.db"));
  if (!db.batch) throw new Error("Missing Scrypted database batch API");
  await db.open();
  try {
    const users: ScryptedUserRecord[] = [];
    for await (const user of db.getAll(ScryptedUser)) {
      if (!api.isUser(user)) throw new Error("Invalid Scrypted user record");
      users.push(user);
    }
    if (users.length > 1 || (users.length === 1 && users[0]?.aclId))
      throw new Error(
        "Scrypted has an unmanaged account; refusing to change it",
      );

    const marker = readMarker(markerFile);
    if (!users.length) {
      if (marker)
        throw new Error(
          "Scrypted administrator disappeared; refusing to recreate it",
        );
      const created = await UsersService.addUserToDatabase(
        db,
        username,
        password,
        undefined,
      );
      if (!api.isUser(created) || !created.token)
        throw new Error("Invalid Scrypted created user record");
      const user = created;
      writeMarker(markerFile, {
        schema: 1,
        credentialDigest,
        tokenDigest: digest(user.token),
      });
      return "created";
    }

    const user = users[0]!;
    if (typeof user.token !== "string" || !user.token)
      throw new Error("Scrypted administrator record is invalid");
    const renamed = user._id !== username;
    if (renamed && marker?.tokenDigest !== digest(user.token))
      throw new Error(
        "Scrypted has an unmanaged account; refusing to rename it",
      );
    if (
      !renamed &&
      marker?.credentialDigest === credentialDigest &&
      marker.tokenDigest === digest(user.token)
    )
      return "unchanged";

    const oldToken = user.token;
    const oldUsername = user._id;
    await setScryptedUserPassword(user, password, Date.now());
    if (
      typeof user.token !== "string" ||
      !user.token ||
      user.token === oldToken
    )
      throw new Error("Scrypted password setter did not rotate the user token");
    if (renamed) {
      user._id = username;
      // LevelDB's batch keeps the account rename atomic. A failed marker write
      // can be retried on the next start without leaving two administrators.
      await db.batch([
        {
          type: "put",
          key: `${ScryptedUser.name}/${username}`,
          value: JSON.stringify(user),
        },
        { type: "del", key: `${ScryptedUser.name}/${oldUsername}` },
      ]);
    } else {
      await db.upsert(user);
    }
    writeMarker(markerFile, {
      schema: 1,
      credentialDigest,
      tokenDigest: digest(user.token),
    });
    return renamed ? "renamed" : "rotated";
  } finally {
    await db.close();
  }
}

export = { reconcile };

if (require.main === module) {
  if (process.argv.length !== 6)
    throw new Error("Invalid Scrypted auth arguments");
  reconcile(
    process.argv[2]!,
    process.argv[3]!,
    process.argv[4]!,
    process.argv[5]!,
  )
    .then((result) => console.log(`Scrypted administrator ${result}`))
    .catch((error: unknown) => {
      console.error(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    });
}
