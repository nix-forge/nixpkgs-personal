function record(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
interface AuthModule {
  AuthService: {
    prototype: {
      checkPassword(
        user: Record<string, unknown>,
        password: string,
      ): Promise<unknown>;
    };
  };
}
function authModule(value: unknown): value is AuthModule {
  if (!record(value) || typeof value["AuthService"] !== "function")
    return false;
  const prototype: unknown = value["AuthService"].prototype;
  return record(prototype) && typeof prototype["checkPassword"] === "function";
}
// Exercise the selected UI's verifier against an account made by the runtime helper.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [helper, service] = process.argv.slice(2);
if (!helper || !service)
  throw new Error("Pass the Homebridge helper and authentication service");
const temporary = mkdtempSync(join(tmpdir(), "homebridge-ui-auth-"));
try {
  const username = join(temporary, "username");
  const passwordFile = join(temporary, "password");
  const authFile = join(temporary, "auth.json");
  const password = "synthetic-password-for-compatibility";
  writeFileSync(username, "test-admin\n");
  writeFileSync(passwordFile, `${password}\n`);
  execFileSync("python3", [helper, username, passwordFile, authFile]);

  const users: unknown = JSON.parse(readFileSync(authFile, "utf8"));
  assert.ok(Array.isArray(users) && users.length === 1);
  const user: unknown = users[0];
  assert.ok(record(user));
  const module: unknown = await import(pathToFileURL(service).href);
  assert.ok(authModule(module), "Invalid Homebridge authentication API");
  const verifier = module.AuthService.prototype;
  assert.equal(await verifier.checkPassword(user, password), user);
  await assert.rejects(verifier.checkPassword(user, "wrong-password"));
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
