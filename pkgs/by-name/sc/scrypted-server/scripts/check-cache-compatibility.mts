import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import { createRequire } from "node:module";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

type Loader = ReturnType<typeof createRequire>;
type Format = "cjs" | "esm";
type GlobOptions = {
  cwd: string;
  follow?: boolean;
  nodir?: boolean;
  signal?: AbortSignal;
  fs?: Record<string, unknown>;
};
type Glob = {
  glob: (pattern: string, options: GlobOptions) => Promise<unknown>;
};
type CacheGet = ((
  cache: string,
  key: string,
  options?: { memoize: boolean },
) => Promise<unknown>) & {
  info: (cache: string, key: string) => Promise<unknown>;
};
type Cache = {
  put: (
    cache: string,
    key: string,
    data: Buffer,
    options?: { metadata: Record<string, string> },
  ) => Promise<unknown>;
  get: CacheGet;
  ls: (cache: string) => Promise<unknown>;
  verify: (cache: string) => Promise<unknown>;
  clearMemoized: () => void;
  rm: {
    entry: (cache: string, key: string) => Promise<unknown>;
    content: (cache: string, integrity: string) => Promise<unknown>;
    all: (cache: string) => Promise<unknown>;
  };
};
type CacheInfo = { path: string; integrity: string };
type Rimraf = {
  rimraf: (target: string, options: { glob: boolean }) => Promise<unknown>;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
function hasMethod(value: unknown, name: string): boolean {
  return (
    (isRecord(value) || typeof value === "function") &&
    typeof Reflect.get(value, name) === "function"
  );
}
function isCache(value: unknown): value is Cache {
  return (
    isRecord(value) &&
    ["put", "get", "ls", "verify", "clearMemoized"].every((name) =>
      hasMethod(value, name),
    ) &&
    hasMethod(value["get"], "info") &&
    ["entry", "content", "all"].every((name) => hasMethod(value["rm"], name))
  );
}
function isGlob(value: unknown): value is Glob {
  return hasMethod(value, "glob");
}
function isRimraf(value: unknown): value is Rimraf {
  return hasMethod(value, "rimraf");
}
function strings(value: unknown): string[] {
  assert.ok(
    Array.isArray(value) &&
      value.every((entry: unknown) => typeof entry === "string"),
  );
  return value;
}
function info(value: unknown): CacheInfo {
  assert.ok(isRecord(value));
  assert.ok(
    typeof value["path"] === "string" && typeof value["integrity"] === "string",
  );
  return { path: value["path"], integrity: value["integrity"] };
}
function version(require: Loader, name: string): string {
  const manifest: unknown = require(name + "/package.json");
  assert.ok(isRecord(manifest) && typeof manifest["version"] === "string");
  return manifest["version"];
}
function requireAt(root: string): Loader {
  return createRequire(path.resolve(root, "package.json"));
}
function assertInside(root: string, candidate: string): void {
  const relative = path.relative(root, candidate);
  assert.ok(relative && !path.isAbsolute(relative));
  assert.ok(relative !== ".." && !relative.startsWith(".." + path.sep));
}
async function loadGlob(appRoot: string, format: Format): Promise<Glob> {
  const appRequire = requireAt(appRoot);
  const cacheRequire = createRequire(appRequire.resolve("cacache"));
  let value: unknown;
  if (format === "cjs") {
    value = cacheRequire("glob");
  } else {
    const manifestPath = cacheRequire.resolve("glob/package.json");
    const manifest: unknown = cacheRequire("glob/package.json");
    assert.ok(isRecord(manifest));
    const exports = manifest["exports"];
    assert.ok(isRecord(exports));
    const root = exports["."];
    assert.ok(isRecord(root));
    const imported = root["import"];
    assert.ok(isRecord(imported) && typeof imported["default"] === "string");
    const entry = path.resolve(path.dirname(manifestPath), imported["default"]);
    value = await import(pathToFileURL(entry).href);
  }
  assert.ok(isGlob(value));
  return value;
}

const cancelPrefix = "CACHE_CHECK_CANCEL:";

// Run this mode in a finite worker process. Its exit event observes counters
// after filesystem work drains, instead of treating promise rejection as drain.
async function cancelWorker(
  appRoot: string,
  cwd: string,
  format: Format,
): Promise<void> {
  const glob = await loadGlob(appRoot, format);
  const controller = new AbortController();
  const reason = new Error("fixture cancellation");
  let reads = 0;
  let readsAtReject = -1;
  let rejected = false;
  let sameReason = false;
  function countRead(): void {
    reads += 1;
    if (reads === 1) controller.abort(reason);
  }
  const observedFs: Record<string, unknown> = {
    ...fs,
    readdir: (...args: unknown[]): unknown => {
      countRead();
      return Reflect.apply(fs.readdir, fs, args);
    },
    readdirSync: (...args: unknown[]): unknown => {
      countRead();
      return Reflect.apply(fs.readdirSync, fs, args);
    },
  };
  process.once("exit", () => {
    assert.equal(rejected, true, "The aborted walk must reject");
    assert.equal(sameReason, true, "The abort reason must propagate");
    assert.equal(
      reads,
      1,
      "No descendant directory reads may start after cancellation",
    );
    assert.equal(
      reads,
      readsAtReject,
      "Rejection must not leave a background traversal",
    );
    fs.writeSync(
      1,
      cancelPrefix +
        JSON.stringify({ format, reads, readsAtReject, rejected }) +
        "\n",
    );
  });
  try {
    await glob.glob("**/*", { cwd, signal: controller.signal, fs: observedFs });
  } catch (error) {
    rejected = true;
    sameReason = error === reason;
    readsAtReject = reads;
  }
}

function makeCancellationTree(root: string, depth: number): void {
  fs.mkdirSync(root, { recursive: true });
  fs.writeFileSync(path.join(root, "entry.txt"), "fixture");
  if (depth === 0) return;
  for (const name of ["a", "b"])
    makeCancellationTree(path.join(root, name), depth - 1);
}

async function main(): Promise<void> {
  const appRoot = process.argv[2];
  const buildRoot = process.argv[3];
  assert.ok(appRoot, "Pass appRoot, optionally buildRoot before npm prune");
  const require = requireAt(appRoot);
  const cache: unknown = require("cacache");
  assert.ok(isCache(cache));
  const cacheRequire = createRequire(require.resolve("cacache"));
  const cacheGlob = fs.realpathSync(cacheRequire.resolve("glob"));
  const rootGlob = fs.realpathSync(require.resolve("glob"));
  assert.equal(
    cacheGlob,
    rootGlob,
    "The cache must resolve the checked global glob override",
  );
  console.log(
    JSON.stringify({
      cacheVersion: version(require, "cacache"),
      globVersion: version(cacheRequire, "glob"),
      cacheGlob,
      rootGlob,
    }),
  );
  const temporary = fs.mkdtempSync(
    path.join(os.tmpdir(), "scrypted-cache-compatibility-"),
  );
  const outside = path.join(temporary, "outside");
  fs.mkdirSync(outside);
  fs.writeFileSync(path.join(outside, "sentinel.txt"), "outside sentinel");
  try {
    const cacheRoot = path.join(temporary, "cache with spaces");
    const kept = Buffer.from("retained cache bytes");
    const metadata = { fixture: "retained" };
    await test("cacache preserves bytes, metadata and public content information", async () => {
      await cache.put(cacheRoot, "kept", kept, { metadata });
      const result = await cache.get(cacheRoot, "kept", { memoize: false });
      assert.ok(isRecord(result) && Buffer.isBuffer(result["data"]));
      assert.deepEqual(result["data"], kept);
      assert.deepEqual(result["metadata"], metadata);
      const entry = info(await cache.get.info(cacheRoot, "kept"));
      assertInside(cacheRoot, entry.path);
      assert.deepEqual(fs.readFileSync(entry.path), kept);
      const verified = await cache.verify(cacheRoot);
      assert.ok(isRecord(verified));
      assert.equal(verified["verifiedContent"], 1);
      assert.equal(verified["totalEntries"], 1);
      const after = await cache.get(cacheRoot, "kept", { memoize: false });
      assert.ok(isRecord(after));
      assert.deepEqual(after["data"], kept);
      assert.deepEqual(after["metadata"], metadata);
    });
    await test("cacache verifies live bytes and cleans orphaned, damaged and missing content", async () => {
      await cache.put(cacheRoot, "orphan", Buffer.from("orphaned cache bytes"));
      await cache.rm.entry(cacheRoot, "orphan");
      await cache.put(
        cacheRoot,
        "damaged",
        Buffer.from("uncorrupted cache bytes"),
      );
      const damaged = info(await cache.get.info(cacheRoot, "damaged"));
      assertInside(cacheRoot, damaged.path);
      fs.writeFileSync(damaged.path, "changed cache bytes");
      cache.clearMemoized();
      await assert.rejects(cache.get(cacheRoot, "damaged", { memoize: false }));
      await cache.put(cacheRoot, "missing", Buffer.from("missing cache bytes"));
      const missing = info(await cache.get.info(cacheRoot, "missing"));
      await cache.rm.content(cacheRoot, missing.integrity);
      const verified = await cache.verify(cacheRoot);
      assert.ok(isRecord(verified));
      assert.equal(verified["verifiedContent"], 1);
      assert.equal(verified["badContentCount"], 1);
      assert.equal(verified["reclaimedCount"], 2);
      assert.equal(verified["missingContent"], 2);
      assert.equal(verified["totalEntries"], 1);
      const listed = await cache.ls(cacheRoot);
      assert.ok(isRecord(listed));
      assert.deepEqual(Object.keys(listed).toSorted(), ["kept"]);
      await Promise.all(
        ["orphan", "damaged", "missing"].map((key) =>
          assert.rejects(cache.get(cacheRoot, key, { memoize: false })),
        ),
      );
      const retained = await cache.get(cacheRoot, "kept", { memoize: false });
      assert.ok(isRecord(retained));
      assert.deepEqual(retained["data"], kept);
    });
    await test("cacache rm.all matches cache directories and preserves other data", async () => {
      fs.writeFileSync(path.join(cacheRoot, "keep.txt"), "cache-root marker");
      fs.mkdirSync(path.join(cacheRoot, "tmp"), { recursive: true });
      fs.writeFileSync(
        path.join(cacheRoot, "tmp", "marker.txt"),
        "temporary marker",
      );
      fs.symlinkSync(outside, path.join(cacheRoot, "content-external"), "dir");
      await cache.rm.all(cacheRoot);
      assert.equal(
        fs.readFileSync(path.join(outside, "sentinel.txt"), "utf8"),
        "outside sentinel",
      );
      assert.equal(
        fs.readFileSync(path.join(cacheRoot, "keep.txt"), "utf8"),
        "cache-root marker",
      );
      assert.equal(
        fs.readFileSync(path.join(cacheRoot, "tmp", "marker.txt"), "utf8"),
        "temporary marker",
      );
      assert.ok(
        fs
          .readdirSync(cacheRoot)
          .every((name) => !/^(?:content-|index-)/.test(name)),
      );
      const listed = await cache.ls(cacheRoot);
      assert.ok(isRecord(listed));
      assert.deepEqual(Object.keys(listed), []);
      await assert.rejects(cache.get(cacheRoot, "kept", { memoize: false }));
      await cache.rm.all(cacheRoot);
    });
    await Promise.all(
      ["cjs", "esm"].map(async (format) => {
        assert.ok(format === "cjs" || format === "esm");
        const glob = await loadGlob(appRoot, format);
        await test(`glob ${format} preserves ordinary, directory and symlink selection`, async () => {
          const root = path.join(temporary, "glob-" + format);
          fs.mkdirSync(path.join(root, "sub"), { recursive: true });
          fs.mkdirSync(path.join(root, "empty"));
          fs.writeFileSync(path.join(root, "first.txt"), "first");
          fs.writeFileSync(path.join(root, "sub", "second.txt"), "second");
          const expected = [
            "first.txt",
            path.join("sub", "second.txt"),
          ].toSorted();
          const regular = strings(
            await glob.glob("**/*", { cwd: root, nodir: true, follow: false }),
          );
          assert.deepEqual(regular.toSorted(), expected);
          fs.symlinkSync(outside, path.join(root, "linked"), "dir");
          const noFollow = strings(
            await glob.glob("**/*.txt", {
              cwd: root,
              nodir: true,
              follow: false,
            }),
          );
          assert.deepEqual(noFollow.toSorted(), expected);
          const followed = strings(
            await glob.glob("**/*.txt", {
              cwd: root,
              nodir: true,
              follow: true,
            }),
          );
          assert.deepEqual(
            followed.toSorted(),
            [...expected, path.join("linked", "sentinel.txt")].toSorted(),
          );
          const filesOnly = strings(
            await glob.glob("*", { cwd: root, nodir: true, follow: true }),
          );
          assert.deepEqual(filesOnly, ["first.txt"]);
        });
        await test(`glob ${format} cancellation drains without starting descendant reads`, () => {
          const root = path.join(temporary, "cancel-" + format);
          makeCancellationTree(root, 4);
          const result = spawnSync(
            process.execPath,
            [
              fileURLToPath(import.meta.url),
              "--glob-cancel",
              appRoot,
              root,
              format,
            ],
            { encoding: "utf8", timeout: 10000, maxBuffer: 1024 * 1024 },
          );
          assert.ifError(result.error);
          assert.equal(result.signal, null);
          assert.equal(result.status, 0, result.stdout + result.stderr);
          const line = result.stdout
            .split("\n")
            .find((value) => value.startsWith(cancelPrefix));
          assert.ok(line, result.stdout + result.stderr);
          const observed: unknown = JSON.parse(line.slice(cancelPrefix.length));
          assert.ok(isRecord(observed));
          assert.equal(observed["reads"], 1);
          assert.equal(observed["readsAtReject"], 1);
          assert.equal(observed["rejected"], true);
        });
      }),
    );
    if (buildRoot) {
      await test("development rimraf retains glob-enabled deletion before prune", async () => {
        const buildRequire = requireAt(buildRoot);
        const rimraf: unknown = buildRequire("rimraf");
        assert.ok(isRimraf(rimraf));
        const rimrafRequire = createRequire(buildRequire.resolve("rimraf"));
        assert.equal(
          fs.realpathSync(rimrafRequire.resolve("glob")),
          fs.realpathSync(buildRequire.resolve("glob")),
        );
        console.log(
          JSON.stringify({
            rimraf: fs.realpathSync(buildRequire.resolve("rimraf")),
            rimrafGlob: fs.realpathSync(rimrafRequire.resolve("glob")),
          }),
        );
        const root = path.join(temporary, "rimraf with spaces");
        fs.mkdirSync(path.join(root, "sub"), { recursive: true });
        fs.writeFileSync(path.join(root, "first.remove"), "first");
        fs.writeFileSync(path.join(root, "sub", "second.remove"), "second");
        fs.writeFileSync(path.join(root, "keep.txt"), "retained");
        assert.equal(
          await rimraf.rimraf(path.join(root, "**", "*.remove"), {
            glob: true,
          }),
          true,
        );
        assert.equal(fs.existsSync(path.join(root, "first.remove")), false);
        assert.equal(
          fs.existsSync(path.join(root, "sub", "second.remove")),
          false,
        );
        assert.equal(
          fs.readFileSync(path.join(root, "keep.txt"), "utf8"),
          "retained",
        );
        assert.equal(
          fs.readFileSync(path.join(outside, "sentinel.txt"), "utf8"),
          "outside sentinel",
        );
      });
    }
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

if (process.argv[2] === "--glob-cancel") {
  const appRoot = process.argv[3];
  const cwd = process.argv[4];
  const format = process.argv[5];
  assert.ok(appRoot && cwd && (format === "cjs" || format === "esm"));
  await cancelWorker(appRoot, cwd, format);
} else {
  await main();
}
