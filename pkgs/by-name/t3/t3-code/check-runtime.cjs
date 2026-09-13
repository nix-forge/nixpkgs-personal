// Exercise packaged native modules without starting the GUI or opening credentials.
const assert = require("node:assert/strict");
const { createRequire } = require("node:module");
const path = require("node:path");
const [resources, expectedVersion] = process.argv.slice(2);
const appRequire = createRequire(
  path.join(resources, "app.asar", "package.json"),
);
assert.equal(appRequire("./package.json").version, expectedVersion);
for (const name of ["node-pty", "@napi-rs/keyring", "msgpackr-extract"]) {
  appRequire(name);
  console.log(`Loaded ${name}`);
}
console.log(
  `T3 Code ${expectedVersion}: ${process.platform}/${process.arch}, Electron ${process.versions.electron}`,
);
