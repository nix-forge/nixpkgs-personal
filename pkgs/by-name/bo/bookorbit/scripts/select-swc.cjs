const fs = require("node:fs");
const { createRequire } = require("node:module");
const cli = require.resolve("@nestjs/cli/package.json", {
  paths: [process.cwd() + "/server"],
});
const fromCli = createRequire(cli);
const core = fromCli.resolve("@swc/core/package.json");
const fromCore = createRequire(core);
const nativePackage = process.argv[2];
if (typeof nativePackage !== "string" || nativePackage.length === 0) {
  throw new Error("expected selected SWC native package argument");
}
const manifest = fromCore(nativePackage + "/package.json");
const coreManifest = fromCli("@swc/core/package.json");
if (
  coreManifest.name !== "@swc/core" ||
  manifest.name !== nativePackage ||
  typeof manifest.version !== "string" ||
  manifest.version.length === 0 ||
  coreManifest.version !== manifest.version
) {
  throw new Error("unexpected selected SWC native package or version");
}
console.log(
  JSON.stringify({
    path: fs.realpathSync(fromCore.resolve(nativePackage)),
    version: manifest.version,
  }),
);
