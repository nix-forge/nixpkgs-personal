import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { pathToFileURL } from "node:url";

const source = process.argv[2];
const { fixture } = await import(
  pathToFileURL(path.join(source, "pnpm/esm-loader/test/fixture.mjs")).href
);
const cleanup = [];
const setup = fixture({ after: (callback) => cleanup.push(callback) });
try {
  setup.add(
    "example@1",
    {
      "package.json": JSON.stringify({ type: "module", exports: "./index.js" }),
      "index.js":
        "import value from 'legacy'; export default value + ' bundle'",
    },
    { legacy: "legacy@1" },
  );
  setup.add("legacy@1", {
    "package.json": JSON.stringify({ main: "index.cjs" }),
    "index.cjs": "module.exports = 'hello'",
  });
  setup.manifest.packages["."].dependencies.example = "example@1";
  setup.write(".store-manifest.json", JSON.stringify(setup.manifest));
  setup.write(
    "loader.mjs",
    fs.readFileSync(
      path.join(source, "pnpm/crates/deps-restorer/src/cas-loader.mjs.inc"),
    ),
  );
  setup.write("app.mjs", "import value from 'example'; console.log(value)");
  const result = spawnSync(
    process.execPath,
    [
      "--import",
      pathToFileURL(path.join(setup.root, "loader.mjs")).href,
      "app.mjs",
    ],
    {
      cwd: setup.root,
      encoding: "utf8",
    },
  );
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), "hello bundle");
  assert.equal(fs.existsSync(path.join(setup.root, "node_modules")), false);
  console.log(
    "Generated CAS loader resolves ESM and CommonJS from store blobs.",
  );
} finally {
  for (const callback of cleanup) callback();
}
