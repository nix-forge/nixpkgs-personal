import assert = require("node:assert/strict");
import fs = require("node:fs");
import os = require("node:os");
import path = require("node:path");
import vm = require("node:vm");
import nodeNodeTest = require("node:test");
const { test } = nodeNodeTest;
import localManagedLoginCjs = require("./managed-login.cjs");
const { configurePlayer, install, provision } = localManagedLoginCjs;

function fixture(t: import("node:test").TestContext): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "feishin-login-"));
  t.after(() => fs.rmSync(dir, { recursive: true }));
  const username = path.join(dir, "username");
  const password = path.join(dir, "password");
  const settings = path.join(dir, "managed.json");
  fs.writeFileSync(username, "listener\n");
  fs.writeFileSync(password, "test-password\n");
  fs.writeFileSync(
    settings,
    JSON.stringify({
      managed_login: {
        name: "Music",
        url: "http://music.test/",
        username_path: username,
        password_path: password,
      },
    }),
  );
  return settings;
}

void test("repairs a stale session while preserving server identity and unrelated data", async (t) => {
  const settings = fixture(t);
  let store = JSON.stringify({
    version: 2,
    state: {
      deviceId: "device",
      currentServer: null,
      serverList: {
        previous: {
          id: "previous",
          name: "Music",
          username: "obsolete",
          url: "https://music.test",
          musicFolderId: ["folder"],
        },
        other: { id: "other", name: "Other" },
      },
    },
  });
  let reloaded = false;
  const saved: string[][] = [];
  const contents = {
    executeJavaScript: async (expression: string): Promise<unknown> => {
      const result: unknown = vm.runInNewContext(expression, {
        localStorage: {
          getItem: () => store,
          setItem: (_key: string, value: string) => {
            store = value;
          },
        },
        window: {
          api: {
            localSettings: {
              passwordSet: async (...args: string[]) => {
                saved.push(args);
                return true;
              },
            },
          },
        },
      });
      return result;
    },
    reload: () => {
      reloaded = true;
    },
  };
  await provision(contents, settings, async (url, options) => {
    assert.equal(url, "http://music.test/auth/login");
    assert.ok(options && typeof options.body === "string");
    assert.deepEqual(JSON.parse(options.body), {
      username: "listener",
      password: "test-password",
    });
    return Response.json({
      token: "fresh-token",
      id: "user",
      username: "listener",
      subsonicSalt: "salt",
      subsonicToken: "hash",
    });
  });
  const result: unknown = JSON.parse(store);
  assert.ok(result !== null && typeof result === "object");
  const state: unknown = Reflect.get(result, "state");
  assert.ok(state !== null && typeof state === "object");
  const currentServer: unknown = Reflect.get(state, "currentServer");
  assert.ok(currentServer !== null && typeof currentServer === "object");
  const serverList: unknown = Reflect.get(state, "serverList");
  assert.ok(serverList !== null && typeof serverList === "object");
  const other: unknown = Reflect.get(serverList, "other");
  assert.ok(other !== null && typeof other === "object");
  assert.equal(Reflect.get(currentServer, "username"), "listener");
  assert.equal(Reflect.get(currentServer, "ndCredential"), "fresh-token");
  assert.equal(Reflect.get(currentServer, "id"), "previous");
  assert.deepEqual(Reflect.get(currentServer, "musicFolderId"), ["folder"]);
  assert.equal(Reflect.get(other, "name"), "Other");
  assert.equal(Reflect.get(state, "deviceId"), "device");
  assert.deepEqual(saved, [["test-password", "previous"]]);
  assert.equal(reloaded, true);
  assert.equal(store.includes("test-password"), false);
});

void test("failed authentication leaves the session unchanged", async (t) => {
  let modified = false;
  await assert.rejects(
    provision(
      {
        executeJavaScript: () => {
          modified = true;
          return Promise.resolve();
        },
        reload: () => {
          modified = true;
        },
      },
      fixture(t),
      async () => new Response(null, { status: 401 }),
    ),
    /login failed/,
  );
  assert.equal(modified, false);
});

void test("ordinary installations without managed credentials remain usable", async (t) => {
  const settings = fixture(t);
  fs.writeFileSync(settings, "{}");
  assert.equal(
    await provision(
      { executeJavaScript: async () => {}, reload: () => {} },
      settings,
      () => {
        throw new Error("Unexpected network call");
      },
    ),
    false,
  );
});

void test("first-launch migration cannot erase managed player configuration", (t) => {
  const settings = fixture(t);
  const dir = path.dirname(settings);
  fs.writeFileSync(settings, JSON.stringify({ mpv_path: "/managed/mpv" }));
  // This is the upstream >=1.0.0 migration's effect on mutable settings.
  fs.writeFileSync(path.join(dir, "config.json"), "{}");
  const values = new Map<string, string>();
  configurePlayer(
    {
      set: (key, value) => {
        values.set(key, value);
      },
    },
    settings,
  );
  assert.equal(values.get("mpv_path"), "/managed/mpv");
});

void test("startup reads managed policy after the mutable settings were cleared", async (t) => {
  const settings = fixture(t);
  fs.writeFileSync(path.join(path.dirname(settings), "config.json"), "{}");
  const originalFetch = globalThis.fetch;
  t.after(() => {
    globalThis.fetch = originalFetch;
  });
  let requested = false;
  globalThis.fetch = async () => {
    requested = true;
    return Response.json({
      token: "token",
      id: "user",
      username: "listener",
      subsonicSalt: "salt",
      subsonicToken: "hash",
    });
  };
  let loaded: (() => void) | undefined;
  let reloaded = false;
  install({
    app: {
      getPath: () => path.dirname(settings),
      on: (_event, callback) =>
        callback(undefined, {
          getType: () => "window",
          getURL: () => "file:///app/out/renderer/index.html",
          once: (_loadEvent, onLoad) => {
            loaded = onLoad;
          },
          executeJavaScript: async () => {},
          reload: () => {
            reloaded = true;
          },
        }),
    },
  });
  assert.ok(loaded);
  loaded();
  await new Promise<void>((resolve) => setImmediate(resolve));
  assert.equal(requested, true);
  assert.equal(reloaded, true);
});
