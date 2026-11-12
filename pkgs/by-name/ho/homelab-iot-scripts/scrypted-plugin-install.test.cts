import assert = require("node:assert/strict");
import fs = require("node:fs");
import os = require("node:os");
import path = require("node:path");
import localScryptedPluginInstallCjs = require("./scrypted-plugin-install.cjs");
const { install } = localScryptedPluginInstallCjs;

async function main() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "scrypted-plugin-test-"));
  const packageRoot = path.join(root, "package");
  const volume = path.join(root, "volume");
  const manifestFile = path.join(root, "manifest.json");
  const usernameFile = path.join(root, "username");
  const passwordFile = path.join(root, "password");
  const markerFile = path.join(volume, ".nix-managed-plugins.json");
  fs.mkdirSync(path.join(packageRoot, "dist"), { recursive: true });
  fs.mkdirSync(volume);
  fs.writeFileSync(usernameFile, "admin\n");
  fs.writeFileSync(passwordFile, "test-only-long-password-12345\n");
  fs.writeFileSync(
    path.join(packageRoot, "package.json"),
    JSON.stringify({
      name: "@scrypted/arlo",
      version: "1.2.3",
    }),
  );
  fs.writeFileSync(path.join(packageRoot, "dist/plugin.zip"), "test-zip");
  fs.writeFileSync(
    manifestFile,
    JSON.stringify([
      { name: "@scrypted/snapshot", version: "1.0.0", source: "npm" },
      {
        name: "@scrypted/arlo",
        version: "1.2.3",
        source: "local",
        path: packageRoot,
      },
    ]),
  );
  const calls: [string, string][] = [];
  const expectedAuth = `Basic ${Buffer.from("admin:test-only-long-password-12345").toString("base64")}`;
  const transport: NonNullable<Parameters<typeof install>[4]> = async (
    api,
    method,
    route,
    body,
  ) => {
    assert.equal(api.authorization, expectedAuth);
    calls.push([method, route]);
    if (body) assert(Buffer.isBuffer(body));
    return Buffer.from("ok");
  };
  try {
    await install(manifestFile, usernameFile, passwordFile, volume, transport);
    assert.deepEqual(
      calls.map((call) => call[1]),
      [
        "/login",
        "/web/component/script/install/@scrypted/snapshot/1.0.0",
        "/web/component/script/setup?npmPackage=%40scrypted%2Farlo",
        "/web/component/script/deploy?npmPackage=%40scrypted%2Farlo",
      ],
    );
    assert.equal(fs.statSync(markerFile).mode & 0o777, 0o600);
    assert(
      !fs.readFileSync(markerFile, "utf8").includes("test-only-long-password"),
    );

    calls.length = 0;
    await install(manifestFile, usernameFile, passwordFile, volume, transport);
    assert.deepEqual(calls, [["GET", "/login"]]);

    fs.writeFileSync(path.join(packageRoot, "dist/plugin.zip"), "changed-zip");
    const prior = fs.readFileSync(markerFile, "utf8");
    await assert.rejects(
      install(
        manifestFile,
        usernameFile,
        passwordFile,
        volume,
        async (api, method, route, body, contentType) => {
          if (route.includes("/deploy?")) throw new Error("deployment failed");
          return transport(api, method, route, body, contentType);
        },
      ),
      /deployment failed/,
    );
    assert.equal(fs.readFileSync(markerFile, "utf8"), prior);
    await install(manifestFile, usernameFile, passwordFile, volume, transport);
    assert.notEqual(fs.readFileSync(markerFile, "utf8"), prior);
    console.log("Scrypted plugin deployment checks passed");
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
