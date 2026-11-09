import assert from "node:assert/strict";
import { EventEmitter, once } from "node:events";
import http from "node:http";
import { createRequire } from "node:module";
import path from "node:path";
import { test } from "node:test";

const app = process.argv[2];
assert.ok(app, "Pass the installed server directory");
const require = createRequire(path.join(app, "package.json"));
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}
function invoke(target: unknown, name: string, ...args: unknown[]): unknown {
  assert.ok(isRecord(target) || typeof target === "function");
  const method: unknown = Reflect.get(target, name);
  assert.ok(typeof method === "function", "Expected method " + name);
  return Reflect.apply(method, target, args);
}
function constructor(module: unknown, name?: string): Function {
  const value: unknown = name ? invokeProperty(module, name) : module;
  assert.ok(typeof value === "function");
  return value;
}
function invokeProperty(target: unknown, name: string): unknown {
  assert.ok(isRecord(target) || typeof target === "function");
  return Reflect.get(target, name);
}
async function listen(server: http.Server): Promise<string> {
  const ready = once(server, "listening", {
    signal: AbortSignal.timeout(5000),
  });
  server.listen(0, "127.0.0.1");
  await ready;
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  return "http://127.0.0.1:" + address.port;
}
async function close(server: http.Server): Promise<void> {
  server.closeAllConnections();
  await new Promise<void>((resolve, reject) =>
    server.close((error) => (error ? reject(error) : resolve())),
  );
}

await test("Engine.IO retains polling messages, legacy polling and WebSocket upgrades", async () => {
  const engine: unknown = Reflect.construct(
    constructor(require("engine.io"), "Server"),
    [{ allowEIO3: true }],
  );
  assert.ok(engine instanceof EventEmitter);
  const server = http.createServer();
  invoke(engine, "attach", server);
  const sockets = new Map<string, unknown>();
  engine.on("connection", (socket: unknown) => {
    assert.ok(socket instanceof EventEmitter);
    const id = invokeProperty(socket, "id");
    assert.ok(typeof id === "string");
    sockets.set(id, socket);
    socket.on("message", (data: unknown) => {
      assert.ok(typeof data === "string" || Buffer.isBuffer(data));
      invoke(socket, "send", "echo:" + data.toString());
    });
  });
  let client: unknown;
  try {
    const url = await listen(server);
    const greetings = await Promise.all(
      ["4", "3"].map(async (version) => {
        const response = await fetch(
          url + "/engine.io/?EIO=" + version + "&transport=polling",
          { signal: AbortSignal.timeout(5000) },
        );
        assert.equal(response.status, 200);
        const body = await response.text();
        assert.match(body, /0\{"sid":/);
        return { version, body };
      }),
    );
    const greeting = greetings.find((value) => value.version === "4");
    assert.ok(greeting);
    const handshake: unknown = JSON.parse(greeting.body.slice(1));
    assert.ok(isRecord(handshake) && typeof handshake["sid"] === "string");
    const pollingSid = handshake["sid"];
    const polling =
      url +
      "/engine.io/?EIO=4&transport=polling&sid=" +
      encodeURIComponent(pollingSid);
    const sent = await fetch(polling, {
      method: "POST",
      headers: {
        "Content-Type": "text/plain;charset=UTF-8",
        Connection: "close",
      },
      body: "4polling",
      signal: AbortSignal.timeout(5000),
    });
    assert.equal(sent.status, 200);
    assert.equal(await sent.text(), "ok");
    const response = await fetch(polling, {
      signal: AbortSignal.timeout(5000),
    });
    assert.equal(response.status, 200);
    assert.equal(await response.text(), "4echo:polling");
    client = Reflect.construct(constructor(require("ws")), [
      url.replace("http:", "ws:") +
        "/engine.io/?EIO=4&transport=websocket&sid=" +
        encodeURIComponent(pollingSid),
    ]);
    assert.ok(client instanceof EventEmitter);
    const probe: Promise<unknown[]> = once(client, "message", {
      signal: AbortSignal.timeout(5000),
    });
    await once(client, "open", { signal: AbortSignal.timeout(5000) });
    invoke(client, "send", "2probe");
    const [hello]: unknown[] = await probe;
    assert.ok(Buffer.isBuffer(hello));
    assert.equal(hello.toString(), "3probe");
    const socket = sockets.get(pollingSid);
    assert.ok(socket instanceof EventEmitter);
    const upgraded: Promise<unknown[]> = once(socket, "upgrade", {
      signal: AbortSignal.timeout(5000),
    });
    invoke(client, "send", "5");
    const [transport]: unknown[] = await upgraded;
    assert.equal(invokeProperty(transport, "name"), "websocket");
    const echoed: Promise<unknown[]> = once(client, "message", {
      signal: AbortSignal.timeout(5000),
    });
    invoke(client, "send", "4message");
    const [message]: unknown[] = await echoed;
    assert.ok(Buffer.isBuffer(message));
    assert.equal(message.toString(), "4echo:message");
  } finally {
    if (client) invoke(client, "terminate");
    invoke(engine, "close");
    await close(server);
  }
});

await test("WebSocket messages preserve compressed text, binary and fragmented frames", async () => {
  const server = http.createServer();
  const webSocketServer: unknown = Reflect.construct(
    constructor(require("ws"), "WebSocketServer"),
    [{ server, perMessageDeflate: true }],
  );
  assert.ok(webSocketServer instanceof EventEmitter);
  webSocketServer.on("connection", (socket: unknown) => {
    assert.ok(socket instanceof EventEmitter);
    socket.on("message", (data: unknown, binary: unknown) =>
      invoke(socket, "send", data, { binary }),
    );
  });
  let client: unknown;
  try {
    const url = await listen(server);
    client = Reflect.construct(constructor(require("ws")), [
      url.replace("http:", "ws:"),
    ]);
    assert.ok(client instanceof EventEmitter);
    await once(client, "open", { signal: AbortSignal.timeout(5000) });
    assert.equal(invokeProperty(client, "extensions"), "permessage-deflate");
    async function exchange(data: string | Buffer): Promise<void> {
      assert.ok(client instanceof EventEmitter);
      const echoed: Promise<unknown[]> = once(client, "message", {
        signal: AbortSignal.timeout(5000),
      });
      invoke(client, "send", data);
      const [message, binary]: unknown[] = await echoed;
      assert.ok(Buffer.isBuffer(message));
      assert.deepEqual(
        message,
        Buffer.isBuffer(data) ? data : Buffer.from(data),
      );
      assert.equal(binary, Buffer.isBuffer(data));
    }
    await exchange("text");
    await exchange("ordinary compression payload ".repeat(128));
    await exchange(Buffer.from([0, 1, 2, 255]));
    const fragmented: Promise<unknown[]> = once(client, "message", {
      signal: AbortSignal.timeout(5000),
    });
    invoke(client, "send", "first", { fin: false });
    invoke(client, "send", "second", { fin: true });
    const [message]: unknown[] = await fragmented;
    assert.ok(Buffer.isBuffer(message));
    assert.equal(message.toString(), "firstsecond");
  } finally {
    if (client) invoke(client, "terminate");
    invoke(webSocketServer, "close");
    await close(server);
  }
});
