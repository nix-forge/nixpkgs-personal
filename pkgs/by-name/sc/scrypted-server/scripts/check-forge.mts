import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import path from "node:path";
import { test } from "node:test";

const modulePath = process.argv[2];
assert.ok(modulePath, "Pass the installed node-forge directory");
const require = createRequire(import.meta.url);
const forge: unknown = require(modulePath);
function property(target: unknown, name: string): unknown {
  assert.ok(
    (typeof target === "object" && target !== null) ||
      typeof target === "function",
  );
  const value: unknown = Reflect.get(target, name);
  return value;
}
function invoke(target: unknown, name: string, ...args: unknown[]): unknown {
  const method = property(target, name);
  assert.ok(typeof method === "function");
  const value: unknown = Reflect.apply(method, target, args);
  return value;
}
function client() {
  const errors: unknown[] = [];
  const connection = invoke(property(forge, "tls"), "createConnection", {
    server: false,
    verify: () => true,
    connected: () => {},
    closed: () => {},
    tlsDataReady: (value: unknown) =>
      invoke(property(value, "tlsData"), "getBytes"),
    dataReady: (value: unknown) => invoke(property(value, "data"), "getBytes"),
    error: (_connection: unknown, error: unknown) => errors.push(error),
  });
  return { connection, errors };
}
function processRecord(connection: unknown, bytes: Buffer): void {
  invoke(connection, "process", bytes.toString("binary"));
}
function serverHello(compression: number): Buffer {
  const body = Buffer.concat([
    Buffer.from([3, 1]),
    Buffer.alloc(32),
    Buffer.from([0, 0, 47, compression]),
  ]);
  const handshake = Buffer.concat([Buffer.from([2, 0, 0, body.length]), body]);
  return Buffer.concat([
    Buffer.from([22, 3, 1, 0, handshake.length]),
    handshake,
  ]);
}
function readHeader(header: string): unknown {
  require(path.join(modulePath, "lib/http.js"));
  const response = invoke(property(forge, "http"), "createResponse");
  const buffer = invoke(
    property(forge, "util"),
    "createBuffer",
    "HTTP/1.1 200 OK\r\n" + header + "\r\n\r\n",
  );
  assert.equal(invoke(response, "readHeader", buffer), true);
  return response;
}
function checkHttpTrim(long: boolean): void {
  const spaces = long ? "\t ".repeat(256 * 1024) : "  ";
  const value = "start" + spaces + "end";
  const response = readHeader(
    "X-Fixture: " + value + " \t\r\nSet-Cookie: fixture=" + value + "; path=/",
  );
  assert.equal(invoke(response, "getField", "X-Fixture"), value);
  const cookies = invoke(response, "getCookies");
  assert.ok(Array.isArray(cookies));
  assert.equal(cookies.length, 1);
  assert.equal(property(cookies[0], "name"), "fixture");
  assert.equal(property(cookies[0], "value"), value);
  assert.equal(property(cookies[0], "path"), "/");
}

if (process.argv[3] === "http-trim-child") {
  checkHttpTrim(true);
} else {
  await test("TLS ignores records without a live client session", () => {
    const malformedHello = Buffer.from("160301000402000000", "hex");
    for (const state of ["fresh", "closed", "close-notify"]) {
      const { connection, errors } = client();
      if (state !== "fresh") invoke(connection, "handshake");
      if (state === "closed") invoke(connection, "close");
      if (state === "close-notify")
        processRecord(connection, Buffer.from("15030100020100", "hex"));
      assert.doesNotThrow(() => processRecord(connection, malformedHello));
      assert.deepEqual(errors, []);
    }
  });
  await test("malformed handshakes still report ordinary protocol errors", () => {
    const { connection, errors } = client();
    invoke(connection, "handshake");
    assert.doesNotThrow(() =>
      processRecord(connection, Buffer.from("160301000402000000", "hex")),
    );
    assert.ok(errors.length > 0);
  });
  await test("TLS rejects compression methods the client did not offer", () => {
    for (const compression of [1, 255]) {
      const { connection, errors } = client();
      invoke(connection, "handshake");
      assert.doesNotThrow(() =>
        processRecord(connection, serverHello(compression)),
      );
      assert.equal(property(connection, "fail"), true);
      assert.equal(errors.length, 1);
      assert.match(String(property(errors[0], "message")), /compression/i);
    }
  });
  await test("TLS retains the offered null-compression ServerHello", () => {
    const { connection, errors } = client();
    invoke(connection, "handshake");
    processRecord(connection, serverHello(0));
    assert.deepEqual(errors, []);
    assert.equal(property(connection, "fail"), false);
  });
  await test("Ed25519 rejects identity-key forged signatures", () => {
    const identity = Buffer.alloc(32);
    identity[0] = 1;
    for (const message of ["", "public fixture", "different message"]) {
      assert.equal(
        invoke(property(forge, "ed25519"), "verify", {
          message,
          encoding: "utf8",
          publicKey: identity,
          signature: Buffer.concat([identity, Buffer.alloc(32)]),
        }),
        false,
      );
    }
  });
  await test("Ed25519 preserves the valid RFC 8032 test-one signature", () => {
    assert.equal(
      invoke(property(forge, "ed25519"), "verify", {
        message: "",
        encoding: "binary",
        publicKey: Buffer.from(
          "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
          "hex",
        ),
        signature: Buffer.from(
          "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
          "hex",
        ),
      }),
      true,
    );
  });
  await test("HTTP preserves ordinary header and cookie trimming", () =>
    checkHttpTrim(false));
  await test("large HTTP whitespace inputs complete within a bounded child", () => {
    const result = spawnSync(
      process.execPath,
      [import.meta.filename, modulePath, "http-trim-child"],
      {
        timeout: 10000,
        encoding: "utf8",
        maxBuffer: 1024 * 1024,
      },
    );
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
  });
}
