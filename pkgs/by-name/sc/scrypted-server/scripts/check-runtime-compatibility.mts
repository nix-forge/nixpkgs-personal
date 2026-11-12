import assert from "node:assert/strict";
import {
  createHash,
  createPrivateKey,
  createPublicKey,
  X509Certificate,
} from "node:crypto";
import { once } from "node:events";
import fs from "node:fs";
import { createServer } from "node:http";
import { createRequire } from "node:module";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { brotliCompressSync, deflateSync, gzipSync } from "node:zlib";

function property(target: unknown, key: string): unknown {
  assert.ok(
    (typeof target === "object" && target !== null) ||
      typeof target === "function",
  );
  const value: unknown = Reflect.get(target, key);
  return value;
}
function call(fn: unknown, receiver: unknown, args: unknown[] = []): unknown {
  assert.ok(typeof fn === "function");
  const value: unknown = Reflect.apply(fn, receiver, args);
  return value;
}
function invoke(
  target: unknown,
  method: string,
  args: unknown[] = [],
): unknown {
  return call(property(target, method), target, args);
}
function construct(fn: unknown, args: unknown[] = []): unknown {
  assert.ok(typeof fn === "function");
  const value: unknown = Reflect.construct(fn, args);
  return value;
}
function isStringArray(value: unknown): value is string[] {
  return (
    Array.isArray(value) &&
    value.every((entry: unknown) => typeof entry === "string")
  );
}

function solidPixels(count: number, channel: number): Buffer {
  const expected = Buffer.alloc(count * 3);
  for (let index = channel; index < expected.length; index += 3)
    expected[index] = 255;
  return expected;
}

const appRoot = process.argv[2];
const expectedRsvgDirectory = process.argv[3];
assert.ok(appRoot, "Pass the installed Scrypted application directory");
const require = createRequire(path.join(path.resolve(appRoot), "package.json"));
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "scrypted-runtime-"));

try {
  await test("installed ZIP operations preserve files and Python uses the same implementation", () => {
    const admZip: unknown = require("adm-zip");
    const archive = construct(admZip);
    invoke(archive, "addFile", [
      "fixture/content.txt",
      Buffer.from("zip fixture"),
    ]);
    const encoded = invoke(archive, "toBuffer");
    assert.ok(Buffer.isBuffer(encoded));
    const decoded = construct(admZip, [encoded]);
    const entry = invoke(decoded, "getEntry", ["fixture/content.txt"]);
    const content = invoke(entry, "getData");
    assert.ok(Buffer.isBuffer(content));
    assert.equal(content.toString("utf8"), "zip fixture");
    const destination = path.join(temporary, "extracted");
    invoke(decoded, "extractAllTo", [destination, true]);
    assert.equal(
      fs.readFileSync(path.join(destination, "fixture/content.txt"), "utf8"),
      "zip fixture",
    );
    const pythonRequire = createRequire(require.resolve("py"));
    assert.equal(
      fs.realpathSync(pythonRequire.resolve("adm-zip")),
      fs.realpathSync(require.resolve("adm-zip")),
    );
  });

  await test(
    "installed Express routing and body parsers preserve ordinary request data",
    { timeout: 15000 },
    async () => {
      const express: unknown = require("express");
      const bodyParser: unknown = require("body-parser");
      const app = call(express, undefined);
      invoke(app, "post", [
        "/fixture/:id",
        invoke(bodyParser, "json"),
        invoke(bodyParser, "urlencoded", [{ extended: true }]),
        (request: unknown, response: unknown) => {
          invoke(response, "json", [
            {
              id: property(property(request, "params"), "id"),
              body: property(request, "body"),
            },
          ]);
        },
      ]);
      for (const [route, parser] of [
        ["/raw", invoke(bodyParser, "raw")],
        ["/text", invoke(bodyParser, "text")],
        ["/small", invoke(bodyParser, "json", [{ limit: "8b" }])],
      ]) {
        invoke(app, "post", [
          route,
          parser,
          (request: unknown, response: unknown) => {
            const body = property(request, "body");
            invoke(response, "json", [
              { body: Buffer.isBuffer(body) ? body.toString("hex") : body },
            ]);
          },
        ]);
      }
      invoke(app, "use", [
        (
          error: unknown,
          _request: unknown,
          response: unknown,
          _next: unknown,
        ) => {
          const status = property(error, "status");
          assert.ok(typeof status === "number");
          invoke(invoke(response, "status", [status]), "json", [
            { type: property(error, "type") },
          ]);
        },
      ]);
      const server = createServer((request, response) => {
        call(app, undefined, [request, response]);
      });
      try {
        const listening = once(server, "listening");
        server.listen(0, "127.0.0.1");
        await listening;
        const address = server.address();
        assert.ok(address !== null && typeof address === "object");
        const url = `http://127.0.0.1:${address.port}/fixture/hello%20world`;
        await Promise.all(
          (
            [
              [
                "application/json",
                JSON.stringify({ title: "fixture", count: 2 }),
                { title: "fixture", count: 2 },
              ],
              [
                "application/x-www-form-urlencoded",
                "title=hello+world&values%5B%5D=one&values%5B%5D=two",
                { title: "hello world", values: ["one", "two"] },
              ],
            ] satisfies Array<[string, string, unknown]>
          ).map(async ([type, body, expected]) => {
            const response = await fetch(url, {
              method: "POST",
              headers: { "Content-Type": type, Connection: "close" },
              body,
              signal: AbortSignal.timeout(5000),
            });
            assert.equal(response.status, 200);
            const received: unknown = await response.json();
            assert.deepEqual(received, { id: "hello world", body: expected });
          }),
        );
        const base = `http://127.0.0.1:${address.port}`;
        await Promise.all(
          (
            [
              ["gzip", gzipSync],
              ["deflate", deflateSync],
              ["br", brotliCompressSync],
            ] satisfies Array<[string, (input: Buffer) => Buffer]>
          ).map(async ([encoding, compress]) => {
            const response = await fetch(url, {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                "Content-Encoding": encoding,
                Connection: "close",
              },
              body: new Uint8Array(
                compress(Buffer.from('{"compressed":true}')),
              ),
              signal: AbortSignal.timeout(5000),
            });
            assert.equal(response.status, 200);
            const received: unknown = await response.json();
            assert.deepEqual(received, {
              id: "hello world",
              body: { compressed: true },
            });
          }),
        );
        await Promise.all(
          (
            [
              [
                "/raw",
                "application/octet-stream",
                "bytes",
                { body: Buffer.from("bytes").toString("hex") },
              ],
              [
                "/text",
                "text/plain",
                "ordinary text",
                { body: "ordinary text" },
              ],
            ] satisfies Array<[string, string, string, unknown]>
          ).map(async ([route, type, body, expected]) => {
            const response = await fetch(base + route, {
              method: "POST",
              headers: { "Content-Type": type, Connection: "close" },
              body,
              signal: AbortSignal.timeout(5000),
            });
            assert.equal(response.status, 200);
            const received: unknown = await response.json();
            assert.deepEqual(received, expected);
          }),
        );
        await Promise.all(
          (
            [
              ["/fixture/plain", "{", 400, "entity.parse.failed"],
              ["/small", '{"value":"too large"}', 413, "entity.too.large"],
            ] satisfies Array<[string, string, number, string]>
          ).map(async ([route, body, status, type]) => {
            const response = await fetch(base + route, {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Connection: "close",
              },
              body,
              signal: AbortSignal.timeout(5000),
            });
            assert.equal(response.status, status);
            const received: unknown = await response.json();
            assert.deepEqual(received, { type });
          }),
        );
      } finally {
        server.closeAllConnections();
        if (server.listening) {
          await new Promise<void>((resolve, reject) => {
            server.close((error) => (error ? reject(error) : resolve()));
          });
        }
      }
    },
  );

  await test("http-auth retains its CommonJS UUID v4 nonce input contract", () => {
    const authRequire = createRequire(require.resolve("http-auth"));
    const uuid: unknown = authRequire("uuid");
    const value = invoke(uuid, "v4");
    assert.ok(typeof value === "string");
    assert.match(
      value,
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );
    assert.equal(invoke(uuid, "validate", [value]), true);
  });

  await test("Forge preserves ordinary digest and ASN.1 identifier operations", () => {
    const forge: unknown = require("node-forge");
    const digest = invoke(property(property(forge, "md"), "sha256"), "create");
    invoke(digest, "update", ["public fixture", "utf8"]);
    assert.equal(
      invoke(invoke(digest, "digest"), "toHex"),
      createHash("sha256").update("public fixture").digest("hex"),
    );
    const asn1 = property(forge, "asn1");
    const encoded = invoke(
      invoke(asn1, "oidToDer", ["1.2.840.113549.1.1.1"]),
      "getBytes",
    );
    assert.ok(typeof encoded === "string");
    assert.equal(invoke(asn1, "derToOid", [encoded]), "1.2.840.113549.1.1.1");
  });

  await test(
    "compiled certificate creation preserves key, certificate and reuse contracts",
    { timeout: 20000 },
    () => {
      const module: unknown = require(path.join(appRoot, "dist", "cert.js"));
      const generated = invoke(module, "createSelfSignedCertificate", [
        undefined,
      ]);
      const pem = property(generated, "certificate");
      const privatePem = property(generated, "serviceKey");
      assert.ok(typeof pem === "string" && typeof privatePem === "string");
      const certificate = new X509Certificate(pem);
      const key = createPrivateKey(privatePem);
      assert.ok(certificate.verify(certificate.publicKey));
      assert.deepEqual(
        certificate.publicKey.export({ type: "spki", format: "der" }),
        createPublicKey(key).export({ type: "spki", format: "der" }),
      );
      const reused = invoke(module, "createSelfSignedCertificate", [generated]);
      assert.ok(
        reused === generated,
        "An unexpired certificate and key must be reused",
      );
    },
  );

  const sharp: unknown = require("sharp");
  async function pixels(input: Buffer): Promise<Buffer> {
    const image = call(sharp, undefined, [input]);
    const raw = invoke(invoke(image, "removeAlpha"), "raw");
    const result: unknown = await Promise.resolve(invoke(raw, "toBuffer"));
    assert.ok(Buffer.isBuffer(result));
    return result;
  }
  await test(
    "Sharp retains its colour dependency and resizes through PNG encode/decode",
    { timeout: 10000 },
    async () => {
      const sharpRequire = createRequire(require.resolve("sharp"));
      const colour: unknown = sharpRequire("@img/colour");
      assert.ok(
        colour !== null &&
          (typeof colour === "object" || typeof colour === "function"),
      );
      const image = call(sharp, undefined, [
        { create: { width: 2, height: 2, channels: 4, background: "#ff0000" } },
      ]);
      const encoded: unknown = await Promise.resolve(
        invoke(invoke(invoke(image, "resize", [3, 4]), "png"), "toBuffer"),
      );
      assert.ok(Buffer.isBuffer(encoded));
      const metadata: unknown = await Promise.resolve(
        invoke(call(sharp, undefined, [encoded]), "metadata"),
      );
      assert.equal(property(metadata, "width"), 3);
      assert.equal(property(metadata, "height"), 4);
      assert.equal(property(metadata, "format"), "png");
      assert.deepEqual(await pixels(encoded), solidPixels(12, 0));
    },
  );
  await test(
    "Sharp renders ordinary SVG pixels",
    { timeout: 10000 },
    async () => {
      const svg = Buffer.from(
        '<svg xmlns="http://www.w3.org/2000/svg" width="3" height="2"><rect width="3" height="2" fill="#00ff00"/></svg>',
      );
      assert.deepEqual(await pixels(svg), solidPixels(6, 1));
    },
  );
  await test(
    "bounded SVG includes preserve duplicate entity declarations",
    { timeout: 10000 },
    async () => {
      // A small compatibility control, not evidence of reproducing the original crash.
      const declaration = '<!DOCTYPE svg [<!ENTITY fixtureColour "#0000ff">]>';
      const inner = `${declaration}<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2"><rect width="2" height="2" fill="&fixtureColour;"/></svg>`;
      const href = `data:image/svg+xml;base64,${Buffer.from(inner).toString("base64")}`;
      const svg = Buffer.from(
        `${declaration}<svg xmlns="http://www.w3.org/2000/svg" xmlns:xi="http://www.w3.org/2001/XInclude" width="4" height="2"><xi:include href="${href}" parse="xml"/><rect x="2" width="2" height="2" fill="&fixtureColour;"/></svg>`,
      );
      assert.deepEqual(await pixels(svg), solidPixels(8, 2));
    },
  );
  if (expectedRsvgDirectory) {
    await test("SVG rendering uses the expected native librsvg directory", () => {
      const report: unknown = process.report.getReport();
      const sharedObjects = property(report, "sharedObjects");
      assert.ok(isStringArray(sharedObjects));
      const libraries = sharedObjects.filter((file) =>
        path.basename(file).startsWith("librsvg-2.so"),
      );
      assert.ok(libraries.length > 0, "SVG rendering must load librsvg");
      const expected = fs.realpathSync(expectedRsvgDirectory);
      assert.ok(
        fs.statSync(expected).isDirectory(),
        "Expected librsvg path must be a directory",
      );
      for (const library of libraries) {
        const relative = path.relative(expected, fs.realpathSync(library));
        assert.ok(
          relative !== ".." &&
            !relative.startsWith(`..${path.sep}`) &&
            !path.isAbsolute(relative),
          "Loaded librsvg must belong to the expected native dependency",
        );
      }
    });
  }
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
