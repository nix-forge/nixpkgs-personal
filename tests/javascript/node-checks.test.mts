import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
const checker = fileURLToPath(
  new URL("../check_node_modules.mts", import.meta.url),
);
await test("module checks resolve dependencies from the caller and reject broken entrypoints", () => {
  const root = mkdtempSync(join(tmpdir(), "node-checks-"));
  try {
    writeFileSync(join(root, "package.json"), "{}\n");
    const plugin = join(root, "node_modules", "fixture-plugin");
    mkdirSync(plugin, { recursive: true });
    writeFileSync(join(plugin, "index.js"), "module.exports = () => {};\n");
    writeFileSync(join(root, "plugin.mjs"), "export default () => {};\n");
    writeFileSync(join(root, "invalid.mjs"), "export default {};\n");
    const run = (...args: string[]) =>
      spawnSync(process.execPath, [checker, ...args], {
        cwd: root,
        encoding: "utf8",
        timeout: 5000,
      });
    for (const mode of ["require", "plugin-cjs"]) {
      const result = run(mode, "fixture-plugin");
      assert.equal(result.status, 0, result.stderr);
    }
    assert.equal(run("plugin-esm", "plugin.mjs").status, 0);
    writeFileSync(join(plugin, "index.js"), "module.exports = {};\n");
    const broken = run("plugin-cjs", "fixture-plugin");
    assert.equal(broken.status, 1);
    assert.match(broken.stderr, /entrypoint missing/);
    assert.equal(run("plugin-esm", "invalid.mjs").status, 1);
    assert.equal(run("require", "missing-module").status, 1);
    assert.equal(run("unknown", "fixture-plugin").status, 1);
    assert.equal(run().status, 1);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
