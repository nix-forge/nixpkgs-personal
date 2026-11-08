import { readFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import { stripTypeScriptTypes } from "node:module";

const toImportSpecifier = (file: string): string => pathToFileURL(file).href;

interface RequestOptions {
  method?: string;
  redirect?: string;
}

function moduleFunction<Name extends string>(
  value: unknown,
  name: Name,
): value is Record<Name, (...args: never[]) => unknown> {
  return (
    value !== null &&
    typeof value === "object" &&
    typeof Reflect.get(value, name) === "function"
  );
}
const authModule: unknown = await import(
  toImportSpecifier(`${process.cwd()}/src/utils/browser-auth.mts`)
);
function isAuthModule(
  value: unknown,
): value is typeof import("./browser-auth.mts") {
  return moduleFunction(value, "exchangePasswordForToken");
}
if (!isAuthModule(authModule)) throw new Error("Missing authentication helper");
const { exchangePasswordForToken } = authModule;
const auth = {
  server: "https://reader.example.test",
  username: "reader",
  password: "fixture-password",
};
const mediaModule: unknown = await import(
  toImportSpecifier(`${process.cwd()}/src/utils/media-policy.mts`)
);
function isMediaModule(
  value: unknown,
): value is typeof import("./media-policy.mts") {
  return (
    moduleFunction(value, "getExternalHlsFallback") &&
    moduleFunction(value, "chooseCoverImage")
  );
}
if (!isMediaModule(mediaModule)) throw new Error("Missing media helpers");
const { getExternalHlsFallback, chooseCoverImage } = mediaModule;
void test("external HLS has a safe fallback while native and local playback remain", () => {
  const remote = "https://media.example.test/video.m3u8";
  assert.equal(getExternalHlsFallback(remote, "", auth.server, false), remote);
  assert.equal(getExternalHlsFallback(remote, "", auth.server, true), null);
  assert.equal(
    getExternalHlsFallback("/video.m3u8", "", auth.server, false),
    null,
  );
  assert.equal(
    getExternalHlsFallback(
      "javascript:alert(1)",
      "application/x-mpegurl",
      auth.server,
      false,
    ),
    null,
  );
  assert.equal(
    getExternalHlsFallback(
      "https://media.example.test/video.mp4",
      "video/mp4",
      auth.server,
      false,
    ),
    null,
  );
});
void test("password is exchanged for an application key and discarded", async () => {
  const calls: [string, RequestOptions][] = [];
  const request = async (url: string, options: RequestOptions) => {
    calls.push([url, options]);
    return options.method === "POST" ? { token: "fixture-token" } : [];
  };
  const session = await exchangePasswordForToken(auth, request, auth.server);
  assert.deepEqual(session, {
    server: auth.server,
    token: "fixture-token",
    username: "",
    password: "",
  });
  assert.equal(calls.length, 2);
  assert.ok(calls[1]);
  assert.equal(calls[1][1].redirect, "error");
});
void test("repeat sign-in reuses only this deployment's key", async () => {
  let count = 0;
  const request = async () => {
    count++;
    return [
      { description: "Other app", token: "other" },
      { description: `ReactFlux ${auth.server}`, token: "existing" },
    ];
  };
  assert.equal(
    (await exchangePasswordForToken(auth, request, auth.server)).token,
    "existing",
  );
  assert.equal(count, 1);
});
void test("missing API key fails closed without persisting a password", async () => {
  await assert.rejects(
    exchangePasswordForToken(
      auth,
      async (_url: string, options: RequestOptions) =>
        options.method ? {} : [],
      auth.server,
    ),
  );
});
void test("supplied API key requires no password exchange", async () => {
  const session = await exchangePasswordForToken(
    { ...auth, token: "provided" },
    () => assert.fail(),
    auth.server,
  );
  assert.equal(session.password, "");
  assert.equal(session.token, "provided");
});
void test("session storage keeps only token and server; logout clears it", () => {
  const map = new Map<string, string>();
  const storage = {
    getItem: (key: string) => map.get(key),
    setItem: (key: string, value: string) => map.set(key, value),
    removeItem: (key: string) => map.delete(key),
  };
  const atom = <T,>(value: T) => {
    let subscriber: (next: T) => void = () => {};
    return {
      subscribe: (fn: (next: T) => void) => {
        subscriber = fn;
        fn(value);
      },
      set: (next: T) => subscriber(next),
    };
  };
  let source = stripTypeScriptTypes(
    readFileSync("src/store/authState.mts", "utf8"),
  )
    .replace('import { atom } from "nanostores"', "")
    .replaceAll("export const", "const");
  source +=
    '\nsetAuth({server: "https://reader.example.test", token: "fixture-token", username: "reader", password: "must-not-persist"});';
  vm.runInNewContext(source, {
    atom,
    sessionStorage: storage,
    localStorage: storage,
  });
  const stored = map.get("reactflux-session");
  assert.ok(stored);
  const value: unknown = JSON.parse(stored);
  assert.deepEqual(value, { server: auth.server, token: "fixture-token" });
  vm.runInNewContext(source + "\nresetAuth();", {
    atom,
    sessionStorage: storage,
    localStorage: storage,
  });
  assert.equal(map.size, 0);
});

void test("covers use a supplied sharper bounded rendition without altering signed URLs", () => {
  const small =
    "https://images.example.test/photo.jpg?width=140&s=small-signature";
  const large =
    "https://images.example.test/photo.jpg?width=700&s=large-signature";
  assert.equal(
    chooseCoverImage([
      { url: small },
      { url: large },
      { url: "https://images.example.test/photo.jpg?width=4800" },
      { url: "https://images.example.test/other.jpg?width=1000" },
    ]),
    large,
  );
  assert.equal(chooseCoverImage([{ url: small }]), small);
  assert.equal(chooseCoverImage([]), null);
});
