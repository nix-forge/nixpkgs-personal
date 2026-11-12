import api = require("./scrypted-api.cjs");
// While Scrypted is stopped, remove ledger entries for plugins absent from its
// database. The authenticated installer will restore those declared plugins.
import fs = require("node:fs");
import path = require("node:path");
import crypto = require("node:crypto");
import localScryptedPluginInstallCjs = require("./scrypted-plugin-install.cjs");
const { readManifest, readMarker, writeMarker } = localScryptedPluginInstallCjs;

type Plugin = ReturnType<typeof readManifest>[number];

interface PluginRecord {
  zip?: string;
  packageJson?: { name?: string; version?: string };
}

function localZipMatches(expected: Plugin, actual: PluginRecord): boolean {
  if (expected.source !== "local") return true;
  if (typeof actual.zip !== "string") return false;
  const actualHash = crypto
    .createHash("sha256")
    .update(Buffer.from(actual.zip, "base64"))
    .digest("hex");
  const expectedHash = crypto
    .createHash("sha256")
    .update(fs.readFileSync(path.join(expected.path, "dist/plugin.zip")))
    .digest("hex");
  return actualHash === expectedHash;
}

async function reconcile(
  serverRoot: string,
  volume: string,
  manifestFile: string,
): Promise<"updated" | "unchanged"> {
  const markerFile = path.join(volume, ".nix-managed-plugins.json");
  if (!fs.existsSync(markerFile)) return "unchanged";
  const marker = readMarker(markerFile);
  const desired = new Map(
    readManifest(manifestFile).map((plugin) => [plugin.name, plugin]),
  );
  const WrappedLevel = api.loadDatabase(serverRoot);
  const Plugin = api.loadModel(serverRoot, "Plugin");
  const db = new WrappedLevel(path.join(volume, "scrypted.db"));
  if (!db.tryGet) throw new Error("Missing Scrypted database lookup API");
  await db.open();
  let changed = false;
  try {
    for (const name of Object.keys(marker.installed)) {
      if (!/^@scrypted\/[a-z0-9-]+$/.test(name))
        throw new Error("Invalid Scrypted plugin marker name");
      const expected = desired.get(name);
      // A removed declaration is an attended Scrypted uninstall; do not
      // remove devices or plugin state as a side effect of a Nix switch.
      if (!expected) continue;
      const candidate = await db.tryGet(Plugin, name);
      if (candidate !== undefined && !api.isPlugin(candidate))
        throw new Error("Invalid Scrypted plugin record");
      const actual = candidate;
      if (
        actual?.packageJson?.name === name &&
        actual.packageJson.version === expected.version &&
        localZipMatches(expected, actual)
      )
        continue;
      delete marker.installed[name];
      changed = true;
    }
  } finally {
    await db.close();
  }
  if (changed) writeMarker(markerFile, marker);
  return changed ? "updated" : "unchanged";
}

export = { reconcile };

if (require.main === module) {
  if (process.argv.length !== 5)
    throw new Error("Invalid Scrypted plugin marker arguments");
  reconcile(process.argv[2]!, process.argv[3]!, process.argv[4]!)
    .then((result) => console.log(`Scrypted plugin marker ${result}`))
    .catch((error: unknown) => {
      console.error(error instanceof Error ? error.message : String(error));
      process.exitCode = 1;
    });
}
