// Install pinned Scrypted plugins through its authenticated deployment API.
// The marker records completed versions, never credentials or session tokens.
import scryptedAPI = require("./scrypted-api.cjs");
import crypto = require("node:crypto");
import fs = require("node:fs");
import https = require("node:https");
import path = require("node:path");

type Plugin = { name: string; version: string } & (
  { source: "npm" } | { source: "local"; path: string }
);

interface Marker {
  schema: 1;
  installed: Record<string, string>;
}

interface Api {
  authorization: string;
}

type Transport = (
  api: Api,
  method: string,
  route: string,
  body?: Buffer,
  contentType?: string,
) => Promise<Buffer>;

function credential(file: string): string {
  const value = fs.readFileSync(file, "utf8").replace(/\n$/, "");
  if (!value || /[\r\n\0]/.test(value))
    throw new Error("Invalid Scrypted credential");
  return value;
}

function markerKey(plugin: Plugin): string {
  if (plugin.source === "npm") return `${plugin.name}@${plugin.version}`;
  const metadata = fs.readFileSync(path.join(plugin.path, "package.json"));
  const zip = fs.readFileSync(path.join(plugin.path, "dist/plugin.zip"));
  const parsed: unknown = JSON.parse(metadata.toString("utf8"));
  if (
    !scryptedAPI.record(parsed) ||
    parsed["name"] !== plugin.name ||
    parsed["version"] !== plugin.version
  )
    throw new Error(
      `Scrypted plugin artifact identity mismatch: ${plugin.name}`,
    );
  const hash = crypto
    .createHash("sha256")
    .update(metadata)
    .update(zip)
    .digest("hex");
  return `${plugin.name}@${plugin.version}:${hash}`;
}

function request(
  api: Api,
  method: string,
  route: string,
  body?: Buffer,
  contentType?: string,
): Promise<Buffer> {
  return new Promise<Buffer>((resolve, reject) => {
    const headers: Record<string, string | number> = {
      authorization: api.authorization,
    };
    if (contentType) headers["content-type"] = contentType;
    if (body) headers["content-length"] = body.length;
    const call = https.request(
      {
        hostname: "127.0.0.1",
        port: 10443,
        path: route,
        method,
        headers,
        rejectUnauthorized: false,
        timeout: 600000,
      },
      (response) => {
        const chunks: Buffer[] = [];
        response.on("data", (chunk: Buffer) => chunks.push(chunk));
        response.on("end", () => {
          if (
            response.statusCode === undefined ||
            response.statusCode < 200 ||
            response.statusCode >= 300
          ) {
            reject(
              new Error(
                `Scrypted plugin API returned HTTP ${response.statusCode}`,
              ),
            );
            return;
          }
          resolve(Buffer.concat(chunks));
        });
      },
    );
    call.on("timeout", () =>
      call.destroy(new Error("Scrypted plugin API timed out")),
    );
    call.on("error", reject);
    call.end(body);
  });
}

async function ready(api: Api, transport: Transport): Promise<void> {
  for (let attempt = 0; attempt < 60; attempt++) {
    try {
      await transport(api, "GET", "/login");
      return;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 1000));
    }
  }
  throw new Error("Scrypted did not become ready for plugin installation");
}

function readMarker(file: string): Marker {
  if (!fs.existsSync(file)) return { schema: 1, installed: {} };
  const parsed: unknown = JSON.parse(fs.readFileSync(file, "utf8"));
  const installed: unknown =
    parsed && typeof parsed === "object"
      ? Reflect.get(parsed, "installed")
      : undefined;
  if (
    !parsed ||
    typeof parsed !== "object" ||
    Reflect.get(parsed, "schema") !== 1 ||
    !installed ||
    Array.isArray(installed) ||
    typeof installed !== "object" ||
    !Object.values(installed).every((value) => typeof value === "string")
  )
    throw new Error("Invalid Scrypted plugin marker");
  return {
    schema: 1,
    installed: Object.fromEntries(Object.entries(installed)),
  };
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

function readManifest(manifestFile: string): Plugin[] {
  const parsed: unknown = JSON.parse(fs.readFileSync(manifestFile, "utf8"));
  if (!Array.isArray(parsed) || !parsed.length)
    throw new Error("No Scrypted plugins declared");
  const names = new Set<string>();
  const manifest: Plugin[] = [];
  for (const item of parsed as unknown[]) {
    if (!item || typeof item !== "object")
      throw new Error("Invalid Scrypted plugin manifest");
    const name: unknown = Reflect.get(item, "name");
    const version: unknown = Reflect.get(item, "version");
    const source: unknown = Reflect.get(item, "source");
    const artifactPath: unknown = Reflect.get(item, "path");
    if (
      typeof name !== "string" ||
      !/^@scrypted\/[a-z0-9-]+$/.test(name) ||
      typeof version !== "string" ||
      !/^\d+\.\d+\.\d+$/.test(version) ||
      (source !== "npm" && source !== "local") ||
      names.has(name)
    )
      throw new Error("Invalid Scrypted plugin manifest");
    names.add(name);
    if (source === "local") {
      if (typeof artifactPath !== "string")
        throw new Error("Local Scrypted plugin needs an artifact path");
      manifest.push({ name, version, source, path: artifactPath });
    } else {
      manifest.push({ name, version, source });
    }
  }
  return manifest;
}

async function install(
  manifestFile: string,
  usernameFile: string,
  passwordFile: string,
  volume: string,
  transport: Transport = request,
): Promise<void> {
  const manifest = readManifest(manifestFile);
  const api = {
    authorization: `Basic ${Buffer.from(`${credential(usernameFile)}:${credential(passwordFile)}`).toString("base64")}`,
  };
  await ready(api, transport);
  const markerFile = path.join(volume, ".nix-managed-plugins.json");
  const marker = readMarker(markerFile);
  for (const plugin of manifest) {
    const key = markerKey(plugin);
    if (marker.installed[plugin.name] === key) {
      console.log(`Scrypted plugin current: ${plugin.name}`);
      continue;
    }
    if (plugin.source === "npm") {
      await transport(
        api,
        "POST",
        `/web/component/script/install/${plugin.name}/${plugin.version}`,
      );
    } else {
      const metadata = fs.readFileSync(path.join(plugin.path, "package.json"));
      const zip = fs.readFileSync(path.join(plugin.path, "dist/plugin.zip"));
      const route = `/web/component/script/setup?npmPackage=${encodeURIComponent(plugin.name)}`;
      await transport(api, "POST", route, metadata, "application/json");
      await transport(
        api,
        "POST",
        `/web/component/script/deploy?npmPackage=${encodeURIComponent(plugin.name)}`,
        zip,
        "application/octet-stream",
      );
    }
    marker.installed[plugin.name] = key;
    writeMarker(markerFile, marker);
    console.log(`Scrypted plugin installed: ${plugin.name} ${plugin.version}`);
  }
}

export = { install, markerKey, readManifest, readMarker, writeMarker };

if (require.main === module) {
  if (process.argv.length !== 6)
    throw new Error("Invalid Scrypted plugin installer arguments");
  install(
    process.argv[2]!,
    process.argv[3]!,
    process.argv[4]!,
    process.argv[5]!,
  ).catch((error: unknown) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  });
}
