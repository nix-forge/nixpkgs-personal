import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { EventEmitter } from "node:events";
import fs from "node:fs";
import { createRequire } from "node:module";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";
import { gzipSync } from "node:zlib";

type Entry = EventEmitter & { path: string };
type Parser = EventEmitter & { end: (data: Buffer) => void };
type Options = {
  file: string;
  cwd: string;
  sync?: boolean;
  strip?: number;
  filter?: (name: string) => boolean;
  onReadEntry?: (entry: Entry) => void;
};
type Tar = {
  Parser: new () => Parser;
  extract: (options: Options) => Promise<void>;
  list: (options: Options, files: string[]) => Promise<void>;
  replace: (options: Options, files: string[]) => void;
};
type EntrySummary = { name: string; size: number; digest: string };
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
function isTar(value: unknown): value is Tar {
  return (
    isRecord(value) &&
    ["Parser", "extract", "list", "replace"].every(
      (name) => typeof value[name] === "function",
    )
  );
}
function isEntry(value: unknown): value is Entry {
  return (
    isRecord(value) &&
    typeof value["path"] === "string" &&
    typeof value["on"] === "function"
  );
}
async function loadTar(modulePath: string, esm: boolean): Promise<Tar> {
  let value: unknown;
  if (esm) {
    const manifest: unknown = JSON.parse(
      fs.readFileSync(path.join(modulePath, "package.json"), "utf8"),
    );
    assert.ok(isRecord(manifest));
    const exports = manifest["exports"];
    assert.ok(isRecord(exports));
    const root = exports["."];
    assert.ok(isRecord(root));
    const condition = root["import"];
    assert.ok(isRecord(condition));
    const entry = condition["default"];
    assert.ok(typeof entry === "string");
    value = await import(pathToFileURL(path.resolve(modulePath, entry)).href);
  } else {
    value = createRequire(import.meta.url)(modulePath);
  }
  assert.ok(isTar(value), "Expected the installed tar API");
  return value;
}

function digest(data: Buffer): string {
  return createHash("sha256").update(data).digest("hex");
}
async function parseArchive(tar: Tar, data: Buffer): Promise<EntrySummary[]> {
  const entries: EntrySummary[] = [];
  const parser = new tar.Parser();
  await new Promise<void>((resolve, reject) => {
    parser.on("entry", (value: unknown) => {
      assert.ok(isEntry(value));
      const hash = createHash("sha256");
      let size = 0;
      value.on("data", (chunk: unknown) => {
        assert.ok(Buffer.isBuffer(chunk));
        size += chunk.length;
        hash.update(chunk);
      });
      value.on("end", () =>
        entries.push({ name: value.path, size, digest: hash.digest("hex") }),
      );
    });
    parser.on("error", reject);
    parser.on("end", resolve);
    parser.end(data);
  });
  return entries;
}

// Supply archives at the network boundary while running the compiled installation method.
async function installArchive(app: string, data: Buffer): Promise<unknown> {
  const require = createRequire(path.join(app, "package.json"));
  function moduleRecord(name: string): Record<string, unknown> {
    const value: unknown = require(path.join(app, "dist", name));
    assert.ok(isRecord(value));
    return value;
  }
  const fetch = moduleRecord("fetch/http-fetch.js");
  const service = moduleRecord("services/plugin.js");
  const originalFetch = fetch["httpFetch"];
  const originalInfo = service["getNpmPackageInfo"];
  fetch["httpFetch"] = async () => ({ body: data });
  service["getNpmPackageInfo"] = async () => ({
    versions: {
      "1.0.0": { dist: { tarball: "https://registry.invalid/fixture.tgz" } },
    },
  });
  try {
    const runtime = moduleRecord("runtime.js");
    const constructor = runtime["ScryptedRuntime"];
    assert.ok(typeof constructor === "function");
    const prototype: unknown = Reflect.get(constructor, "prototype");
    assert.ok(isRecord(prototype));
    const install = prototype["installNpm"];
    assert.ok(typeof install === "function");
    let stored: unknown;
    const context = {
      datastore: {
        tryGet: async () => undefined,
        upsert: async (plugin: unknown) => {
          stored = plugin;
        },
      },
      installPlugin: async (plugin: unknown) => {
        assert.equal(plugin, stored);
        return "installed";
      },
    };
    const result: unknown = await Reflect.apply(install, context, [
      "fixture",
      "1.0.0",
    ]);
    assert.equal(result, "installed");
    assert.ok(isRecord(stored));
    const json = stored["packageJson"];
    assert.ok(isRecord(json));
    const encoded = stored["zip"];
    assert.ok(typeof encoded === "string");
    const zip = Buffer.from(encoded, "base64");
    assert.equal(encoded, zip.toString("base64"));
    return { name: json["name"], zipSize: zip.length, zipDigest: digest(zip) };
  } finally {
    fetch["httpFetch"] = originalFetch;
    service["getNpmPackageInfo"] = originalInfo;
  }
}

const resultPrefix = "TAR_CHECK_RESULT:";
async function worker(): Promise<void> {
  const [mode, modulePath, archiveFile, cwd, app] = process.argv.slice(3);
  assert.ok(mode && modulePath && archiveFile && cwd);
  const tar = await loadTar(modulePath, mode.endsWith("-esm"));
  const operation = mode.replace(/-esm$/, "");
  try {
    let result: unknown;
    if (operation === "parse") {
      result = {
        entries: await parseArchive(tar, fs.readFileSync(archiveFile)),
      };
    } else if (operation === "runtime") {
      assert.ok(app);
      result = {
        installed: await installArchive(app, fs.readFileSync(archiveFile)),
      };
    } else if (operation === "extract") {
      await tar.extract({ file: archiveFile, cwd });
    } else if (operation === "headers") {
      await tar.extract({
        file: archiveFile,
        cwd,
        strip: 1,
        filter: (name) => name.endsWith(".h"),
      });
    } else if (operation === "selected") {
      const entries: string[] = [];
      await tar.list(
        {
          file: archiveFile,
          cwd,
          onReadEntry: (entry) => entries.push(entry.path),
        },
        ["wanted.txt"],
      );
      result = { entries };
    } else if (operation === "replace") {
      tar.replace({ file: archiveFile, cwd, sync: true }, ["good.txt"]);
    } else {
      throw new Error("Unknown tar check worker mode");
    }
    console.log(resultPrefix + JSON.stringify({ ok: true, result }));
  } catch (error) {
    const code = isRecord(error) ? error["code"] : undefined;
    console.log(resultPrefix + JSON.stringify({ ok: false, code }));
  }
}

function checksum(block: Buffer): void {
  block.fill(0x20, 148, 156);
  const sum = block.reduce((total, byte) => total + byte, 0);
  block.write(sum.toString(8).padStart(6, "0") + "\0 ", 148, 8, "ascii");
}
function header(name: string, size: number, type: string, link = ""): Buffer {
  const value = Buffer.alloc(512);
  assert.ok(Buffer.byteLength(name) <= 100 && Buffer.byteLength(link) <= 100);
  value.write(name, 0, 100);
  value.write("0000644\0", 100, 8, "ascii");
  value.write("0000000\0", 108, 8, "ascii");
  value.write("0000000\0", 116, 8, "ascii");
  value.write(size.toString(8).padStart(11, "0") + "\0", 124, 12, "ascii");
  value.write("00000000000\0", 136, 12, "ascii");
  value.write(type, 156, 1, "ascii");
  value.write(link, 157, 100);
  value.write("ustar\0", 257, 6, "ascii");
  value.write("00", 263, 2, "ascii");
  checksum(value);
  return value;
}
function member(
  name: string,
  body: Buffer = Buffer.alloc(0),
  type = "0",
  link = "",
): Buffer {
  return Buffer.concat([
    header(name, body.length, type, link),
    body,
    Buffer.alloc((512 - (body.length % 512)) % 512),
  ]);
}
function archive(...members: Buffer[]): Buffer {
  return Buffer.concat([...members, Buffer.alloc(1024)]);
}
function pax(fields: Record<string, string>): Buffer {
  return Buffer.from(
    Object.entries(fields)
      .map(([key, value]) => {
        const suffix = " " + key + "=" + value + "\n";
        let length = Buffer.byteLength(suffix) + 1;
        while (length !== Buffer.byteLength(suffix) + String(length).length) {
          length = Buffer.byteLength(suffix) + String(length).length;
        }
        return String(length) + suffix;
      })
      .join(""),
  );
}

async function main(): Promise<void> {
  const argument = process.argv[2];
  const app = process.argv[3];
  assert.ok(
    argument,
    "Pass the installed tar directory, optionally the installed Scrypted server",
  );
  const modulePath = argument;
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "scrypted-tar-"));
  const script = fileURLToPath(import.meta.url);
  function run(
    mode: string,
    data: Buffer | ((directory: string) => Buffer),
  ): { result: Record<string, unknown>; directory: string } {
    const directory = fs.mkdtempSync(path.join(temporary, "case-"));
    const cwd = path.join(directory, "extract");
    fs.mkdirSync(cwd);
    fs.writeFileSync(path.join(directory, "outside"), "sentinel");
    fs.writeFileSync(path.join(cwd, "good.txt"), "good");
    const file = path.join(directory, "input.tar");
    fs.writeFileSync(file, typeof data === "function" ? data(directory) : data);
    const output = spawnSync(
      process.execPath,
      [script, "--worker", mode, modulePath, file, cwd, ...(app ? [app] : [])],
      {
        timeout: 10000,
        encoding: "utf8",
        maxBuffer: 1024 * 1024,
        env: {
          ...process.env,
          SCRYPTED_VOLUME: path.join(directory, "volume"),
        },
      },
    );
    assert.ifError(output.error);
    assert.equal(output.status, 0, output.stderr);
    assert.equal(output.signal, null);
    const line = output.stdout
      .split("\n")
      .findLast((value) => value.startsWith(resultPrefix));
    assert.ok(line, output.stdout + output.stderr);
    const result: unknown = JSON.parse(line.slice(resultPrefix.length));
    assert.ok(isRecord(result));
    assert.equal(
      fs.readFileSync(path.join(directory, "outside"), "utf8"),
      "sentinel",
    );
    return { result, directory };
  }
  const manifest = Buffer.from(
    JSON.stringify({
      name: "fixture",
      version: "1.0.0",
      scrypted: { pluginDependencies: [] },
    }),
  );
  const plugin = Buffer.from("plugin-fixture");
  const normal = gzipSync(
    archive(
      member("package/package.json", manifest),
      member("package/dist/plugin.zip", plugin),
    ),
  );
  const bomb = gzipSync(
    archive(
      member("package/package.json", manifest),
      member("package/dist/plugin.zip", Buffer.alloc(8 * 1024 * 1024)),
    ),
  );
  try {
    await test("default Parser rejects a high-ratio gzip archive", () => {
      const { result } = run("parse", bomb);
      assert.equal(result["ok"], false);
      assert.equal(result["code"], "TAR_ABORT");
    });
    await test("default Parser preserves normal npm package names and bytes", () => {
      const { result } = run("parse", normal);
      assert.equal(result["ok"], true);
      assert.deepEqual(result["result"], {
        entries: [
          {
            name: "package/package.json",
            size: manifest.length,
            digest: digest(manifest),
          },
          {
            name: "package/dist/plugin.zip",
            size: plugin.length,
            digest: digest(plugin),
          },
        ],
      });
    });
    await test("PAX numeric paths remain strings and NUL paths truncate safely", () => {
      const data = archive(
        member("PaxHeader", pax({ path: "12345" }), "x"),
        member("placeholder", Buffer.from("numeric")),
        member("PaxHeader", pax({ path: "visible.txt\0hidden.txt" }), "x"),
        member("placeholder", Buffer.from("visible")),
      );
      const { result } = run("parse", data);
      assert.equal(result["ok"], true);
      assert.deepEqual(result["result"], {
        entries: [
          { name: "12345", size: 7, digest: digest(Buffer.from("numeric")) },
          {
            name: "visible.txt",
            size: 7,
            digest: digest(Buffer.from("visible")),
          },
        ],
      });
      const extracted = run("extract", data);
      assert.equal(extracted.result["ok"], true);
      assert.equal(
        fs.readFileSync(
          path.join(extracted.directory, "extract/12345"),
          "utf8",
        ),
        "numeric",
      );
      assert.equal(
        fs.readFileSync(
          path.join(extracted.directory, "extract/visible.txt"),
          "utf8",
        ),
        "visible",
      );
    });
    await test("PAX sizes never override GNU long-name/link metadata in either module format", () => {
      for (const kind of ["x", "g"]) {
        for (const suffix of ["", "-esm"]) {
          const { result } = run(
            "parse" + suffix,
            archive(
              member("PaxHeader", pax({ size: "0" }), kind),
              member("LongLink", Buffer.from("long-member-name.txt\0"), "L"),
              member("placeholder"),
              member("visible.txt"),
            ),
          );
          assert.equal(result["ok"], true);
          assert.deepEqual(result["result"], {
            entries: [
              {
                name: "long-member-name.txt",
                size: 0,
                digest: digest(Buffer.alloc(0)),
              },
              { name: "visible.txt", size: 0, digest: digest(Buffer.alloc(0)) },
            ],
          });
          const links = run(
            "extract" + suffix,
            archive(
              member("original", Buffer.from("content")),
              member("PaxHeader", pax({ size: "0" }), kind),
              member("LongLink", Buffer.from("original\0"), "K"),
              member("alias", Buffer.alloc(0), "1", "placeholder"),
            ),
          );
          assert.equal(links.result["ok"], true);
          assert.equal(
            fs.readFileSync(
              path.join(links.directory, "extract/alias"),
              "utf8",
            ),
            "content",
          );
        }
      }
    });
    await test("GNU names and links truncate at the first NUL across newlines", () => {
      for (const suffix of ["", "-esm"]) {
        const extracted = run(
          "headers" + suffix,
          archive(
            member(
              "LongLink",
              Buffer.from("node/include/first.h\0\nsecond\0tail.h\0"),
              "L",
            ),
            member("placeholder", Buffer.from("header")),
            member(
              "LongLink",
              Buffer.from("node/include/first.h\0\nsecond\0tail.h\0"),
              "K",
            ),
            member("node/include/alias.h", Buffer.alloc(0), "1", "placeholder"),
          ),
        );
        assert.equal(extracted.result["ok"], true);
        for (const name of ["first.h", "alias.h"]) {
          assert.equal(
            fs.readFileSync(
              path.join(extracted.directory, "extract/include", name),
              "utf8",
            ),
            "header",
          );
        }
        const valid = run(
          "headers" + suffix,
          archive(
            member(
              "LongLink",
              Buffer.from("node/include/valid\nname.h\0"),
              "L",
            ),
            member("placeholder", Buffer.from("valid")),
          ),
        );
        assert.equal(valid.result["ok"], true);
        assert.equal(
          fs.readFileSync(
            path.join(valid.directory, "extract/include/valid\nname.h"),
            "utf8",
          ),
          "valid",
        );
      }
    });
    await test("selected-member listing bounds GNU and PAX long-path recursion", () => {
      const longName = "x/".repeat(20000) + "deep.txt";
      const { result } = run(
        "selected",
        archive(
          member("LongLink", Buffer.from(longName + "\0"), "L"),
          member("placeholder"),
          member("PaxHeader", pax({ path: longName }), "x"),
          member("placeholder"),
          member("wanted.txt", Buffer.from("wanted")),
        ),
      );
      assert.equal(result["ok"], true);
      assert.deepEqual(result["result"], { entries: ["wanted.txt"] });
    });
    await test("extraction rejects relative and drive-relative hardlink/symlink escapes", () => {
      const { result, directory } = run(
        "extract",
        archive(
          member("a/b/c/link", Buffer.alloc(0), "1", "../outside"),
          member("drive-link", Buffer.alloc(0), "1", "C:../outside"),
          member("a/b/drive-link", Buffer.alloc(0), "2", "C:../../../outside"),
          member("ok.txt", Buffer.from("ok")),
        ),
      );
      assert.equal(result["ok"], true);
      assert.equal(
        fs.existsSync(path.join(directory, "extract/a/b/c/link")),
        false,
      );
      assert.equal(
        fs.existsSync(path.join(directory, "extract/drive-link")),
        false,
      );
      assert.equal(
        fs.existsSync(path.join(directory, "extract/a/b/drive-link")),
        false,
      );
      assert.equal(
        fs.readFileSync(path.join(directory, "extract/ok.txt"), "utf8"),
        "ok",
      );
    });
    await test("absolute hardlink and symlink targets cannot reach outside extraction", () => {
      const { result, directory } = run("extract", (root) =>
        archive(
          member(
            "absolute-hardlink",
            Buffer.alloc(0),
            "1",
            path.join(root, "outside"),
          ),
          member(
            "absolute-symlink",
            Buffer.alloc(0),
            "2",
            path.join(root, "outside"),
          ),
        ),
      );
      assert.equal(result["ok"], true);
      assert.equal(
        fs.existsSync(path.join(directory, "extract/absolute-hardlink")),
        false,
      );
      assert.equal(
        fs.existsSync(path.join(directory, "extract/absolute-symlink")),
        false,
      );
    });
    await test("extraction rejects hardlink escape through an archive symlink chain", () => {
      const { result, directory } = run(
        "extract",
        archive(
          member("a/b/c/up", Buffer.alloc(0), "2", "../.."),
          member("a/b/escape", Buffer.alloc(0), "2", "c/up/../.."),
          member("exfil", Buffer.alloc(0), "1", "a/b/escape/outside"),
        ),
      );
      assert.equal(result["ok"], true);
      assert.equal(fs.existsSync(path.join(directory, "extract/exfil")), false);
    });
    await test("ordinary hardlinks, symlinks and node-gyp header extraction still work", () => {
      const extracted = run(
        "extract",
        archive(
          member("original", Buffer.from("content")),
          member("hardlink", Buffer.alloc(0), "1", "original"),
          member("symlink", Buffer.alloc(0), "2", "original"),
        ),
      );
      assert.equal(extracted.result["ok"], true);
      for (const name of ["original", "hardlink", "symlink"]) {
        assert.equal(
          fs.readFileSync(
            path.join(extracted.directory, "extract", name),
            "utf8",
          ),
          "content",
        );
      }
      const headers = run(
        "headers",
        archive(
          member("node/include/node.h", Buffer.from("header")),
          member("node/ignored.txt", Buffer.from("ignored")),
        ),
      );
      assert.equal(headers.result["ok"], true);
      assert.equal(
        fs.readFileSync(
          path.join(headers.directory, "extract/include/node.h"),
          "utf8",
        ),
        "header",
      );
      assert.equal(
        fs.existsSync(path.join(headers.directory, "extract/ignored.txt")),
        false,
      );
    });
    await test("replace makes progress past a negative base-256 size", () => {
      const negative = header("negative", 0, "0");
      negative.fill(0xff, 124, 136);
      negative[134] = 0xfe;
      negative[135] = 0;
      checksum(negative);
      const { result } = run("replace", archive(negative));
      assert.equal(result["ok"], true);
    });
    if (app) {
      await test("all installed tar consumers resolve the checked library", () => {
        const require = createRequire(path.join(app, "package.json"));
        assert.equal(
          fs.realpathSync(require.resolve("tar")),
          fs.realpathSync(createRequire(import.meta.url).resolve(modulePath)),
        );
        for (const name of ["node-gyp", "cacache"]) {
          assert.equal(
            createRequire(require.resolve(name)).resolve("tar"),
            require.resolve("tar"),
          );
        }
      });
      await test("compiled Scrypted installNpm propagates parser rejection", () => {
        const { result } = run("runtime", bomb);
        assert.equal(result["ok"], false);
        assert.equal(result["code"], "TAR_ABORT");
      });
      await test("compiled Scrypted installNpm preserves ordinary package persistence", () => {
        const { result } = run("runtime", normal);
        assert.equal(result["ok"], true);
        assert.deepEqual(result["result"], {
          installed: {
            name: "fixture",
            zipSize: plugin.length,
            zipDigest: digest(plugin),
          },
        });
      });
    }
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

if (process.argv[2] === "--worker") await worker();
else await main();
