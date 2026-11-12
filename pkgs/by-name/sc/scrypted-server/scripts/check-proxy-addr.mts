import assert from "node:assert/strict";
import { createRequire } from "node:module";
import path from "node:path";
import { test } from "node:test";

type Trust = (address: string, hop: number) => boolean;
type Request = {
  socket: { remoteAddress: string };
  headers: { "x-forwarded-for": string };
};
type ProxyAddr = ((request: Request, trust: Trust) => string) & {
  compile: (subnets: string | string[]) => Trust;
};
function isProxyAddr(value: unknown): value is ProxyAddr {
  return (
    typeof value === "function" &&
    typeof Reflect.get(value, "compile") === "function"
  );
}
const modulePath = process.argv[2];
assert.ok(modulePath, "Pass the installed proxy-addr directory");
const require = createRequire(import.meta.url);
const proxy: unknown = require(modulePath);
assert.ok(isProxyAddr(proxy));

await test("IPv4 and mapped clients cannot match unrelated IPv6 trust ranges", () => {
  for (const subnets of ["::ffff:10.0.0.0/8", "::/1", ["::/1", "10.0.0.0/8"]]) {
    const trust = proxy.compile(subnets);
    assert.equal(trust("203.0.113.8", 0), false);
    assert.equal(trust("::ffff:203.0.113.8", 0), false);
  }
});
await test("valid native and mapped IPv4 subnets retain their boundaries", () => {
  for (const subnet of ["10.0.0.0/8", "::ffff:10.0.0.0/104"]) {
    const trust = proxy.compile(subnet);
    for (const address of ["10.1.2.3", "::ffff:10.1.2.3"]) {
      assert.equal(trust(address, 0), true);
    }
    for (const address of ["11.1.2.3", "::ffff:11.1.2.3", "2001:db8::1"]) {
      assert.equal(trust(address, 0), false);
    }
  }
});
await test("native IPv6 subnets retain their boundaries", () => {
  const trust = proxy.compile("2001:db8::/32");
  assert.equal(trust("2001:db8::1", 0), true);
  assert.equal(trust("2001:db9::1", 0), false);
  assert.equal(trust("203.0.113.8", 0), false);
  assert.equal(trust("::ffff:203.0.113.8", 0), false);
});
await test("untrusted network peers cannot replace their address through forwarded headers", () => {
  for (const subnets of ["::ffff:10.0.0.0/8", "::/1", ["::/1", "10.0.0.0/8"]]) {
    const request = {
      socket: { remoteAddress: "203.0.113.8" },
      headers: { "x-forwarded-for": "198.51.100.24" },
    };
    assert.equal(proxy(request, proxy.compile(subnets)), "203.0.113.8");
  }
});
await test("trusted proxy chains stop at the first untrusted hop", () => {
  const trust = proxy.compile("10.0.0.0/8");
  const request = {
    socket: { remoteAddress: "10.0.0.2" },
    headers: { "x-forwarded-for": "198.51.100.24, 10.0.0.1" },
  };
  assert.equal(proxy(request, trust), "198.51.100.24");
  request.headers["x-forwarded-for"] = "198.51.100.24, 203.0.113.8";
  assert.equal(proxy(request, trust), "203.0.113.8");
});
await test("Scrypted's loopback trust selection preserves local and remote behavior", () => {
  const trust = proxy.compile("loopback");
  for (const address of ["127.0.0.1", "::1", "::ffff:127.0.0.1"]) {
    assert.equal(trust(address, 0), true);
  }
  for (const address of ["203.0.113.8", "::ffff:203.0.113.8", "2001:db8::1"]) {
    assert.equal(trust(address, 0), false);
  }
});
if (process.argv[3]) {
  const app = process.argv[3];
  await test("Express resolves the checked proxy-address implementation", () => {
    const appRequire = createRequire(path.join(app, "package.json"));
    const expressRequire = createRequire(appRequire.resolve("express"));
    assert.equal(
      expressRequire.resolve("proxy-addr"),
      appRequire.resolve("proxy-addr"),
    );
  });
}
