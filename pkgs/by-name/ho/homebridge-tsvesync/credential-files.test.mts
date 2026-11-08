import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import { createRequire } from "node:module";
import path from "node:path";

const require = createRequire(import.meta.url);

const modulePath = process.argv[2];
if (!modulePath) throw new Error("Pass the VeSync credential module");
const credentialModule: unknown = require(modulePath);
assert.ok(
  typeof credentialModule === "object" &&
    credentialModule !== null &&
    "credential" in credentialModule,
  "Expected a credential module export",
);
const credentialExport: unknown = credentialModule.credential;
function isCredentialFunction(
  value: unknown,
): value is (inline: string | undefined, file: string | undefined) => unknown {
  return typeof value === "function";
}
assert.ok(
  isCredentialFunction(credentialExport),
  "Expected credential function",
);
const credential = credentialExport;
const dir = fs.mkdtempSync(path.join(os.tmpdir(), "vesync-credential-"));
try {
  const file = path.join(dir, "credential");
  fs.writeFileSync(file, "file-secret\n", { mode: 0o600 });
  assert.equal(credential("inline-secret", file), "file-secret");
  assert.equal(credential("inline-secret", undefined), "inline-secret");
  assert.equal(credential(undefined, undefined), "");
  assert.throws(() => credential("inline-secret", path.join(dir, "missing")), {
    code: "ENOENT",
  });
} finally {
  fs.rmSync(dir, { recursive: true, force: true });
}
