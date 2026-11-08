import assert = require("node:assert/strict");
import fs = require("node:fs");
import net = require("node:net");
import os = require("node:os");
import path = require("node:path");
import events = require("node:events");
import nodeNodeTest = require("node:test");
const { test } = nodeNodeTest;
import localMpvReadinessCjs = require("./mpv-readiness.cjs");
const { waitForStream, setIpcReady } = localMpvReadinessCjs;

async function connectedSocket(
  server: import("node:net").Server,
): Promise<import("node:net").Socket> {
  const connected: unknown[] = await events.once(server, "connection");
  const [socket] = connected;
  if (!(socket instanceof net.Socket)) {
    throw new TypeError("Server connection did not provide a socket");
  }
  return socket;
}

async function fixture(t: import("node:test").TestContext, ready = true) {
  setIpcReady(false);
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "mpv-readiness-"));
  const socketPath = path.join(directory, "ipc.sock");
  const sockets = new Set<import("node:net").Socket>();
  const server = net.createServer((socket) => {
    sockets.add(socket);
    socket.on("close", () => sockets.delete(socket));
  });
  t.after(async () => {
    for (const socket of sockets) socket.destroy();
    if (server.listening)
      await new Promise<void>((resolve) => server.close(() => resolve()));
    fs.rmSync(directory, { recursive: true, force: true });
  });
  server.listen(socketPath);
  await events.once(server, "listening");
  setIpcReady(ready);
  return { server, socketPath };
}

void test("subscribes once and waits for file-loaded rather than querying repeatedly", async (t) => {
  const { server, socketPath } = await fixture(t);
  const connected = connectedSocket(server);
  const waiting = waitForStream(
    socketPath,
    "new-song",
    new AbortController().signal,
  );
  const socket = await connected;
  socket.setEncoding("utf8");
  let buffer = "";
  const commands: string[] = [];
  const subscribed = Promise.withResolvers<void>();
  socket.on("data", (chunk: string) => {
    buffer += chunk;
    let end: number;
    while ((end = buffer.indexOf("\n")) >= 0) {
      const request: unknown = JSON.parse(buffer.slice(0, end));
      assert.ok(request !== null && typeof request === "object");
      const command: unknown = Reflect.get(request, "command");
      const requestId: unknown = Reflect.get(request, "request_id");
      assert.ok(Array.isArray(command));
      const fields: unknown[] = command;
      assert.ok(typeof fields[0] === "string");
      assert.ok(typeof requestId === "number");
      buffer = buffer.slice(end + 1);
      commands.push(fields[0]);
      const name = fields[0] === "observe_property" ? fields[2] : fields[1];
      if (fields[0] === "observe_property") {
        const data =
          name === "path" ? "old-song" : name === "track-list" ? [] : false;
        socket.write(
          JSON.stringify({ event: "property-change", name, data }) + "\n",
        );
        if (commands.length === 3) subscribed.resolve();
      } else {
        const data =
          name === "path"
            ? "new-song"
            : name === "track-list"
              ? [{ id: 7 }]
              : false;
        socket.write(
          JSON.stringify({
            request_id: requestId,
            error: "success",
            data,
          }) + "\n",
        );
      }
    }
  });
  await subscribed.promise;
  socket.write(JSON.stringify({ event: "file-loaded" }) + "\n");
  assert.deepEqual(await waiting, { stream: "new-song", tracks: [{ id: 7 }] });
  assert.deepEqual(commands, [
    "observe_property",
    "observe_property",
    "observe_property",
    "get_property",
    "get_property",
    "get_property",
  ]);
});

void test("an already loaded stream succeeds from the subscription snapshot", async (t) => {
  const { server, socketPath } = await fixture(t);
  const connected = connectedSocket(server);
  const waiting = waitForStream(
    socketPath,
    "song",
    new AbortController().signal,
  );
  const socket = await connected;
  socket.write(
    [
      { event: "property-change", name: "track-list", data: [] },
      { event: "property-change", name: "idle-active", data: false },
      { event: "property-change", name: "path", data: "song" },
    ]
      .map((message) => JSON.stringify(message))
      .join("\n") + "\n",
  );
  assert.deepEqual(await waiting, { stream: "song", tracks: [] });
});

void test("a final property event establishes readiness after an idle snapshot", async (t) => {
  const { server, socketPath } = await fixture(t);
  const connected = connectedSocket(server);
  const waiting = waitForStream(
    socketPath,
    "song",
    new AbortController().signal,
  );
  const socket = await connected;
  socket.write(
    [
      { event: "property-change", name: "path", data: "song" },
      { event: "property-change", name: "track-list", data: [] },
      { event: "property-change", name: "idle-active", data: true },
      { event: "property-change", name: "idle-active", data: false },
    ]
      .map((message) => JSON.stringify(message))
      .join("\n") + "\n",
  );
  assert.deepEqual(await waiting, { stream: "song", tracks: [] });
});

void test("snapshot replies may arrive before the path reply", async (t) => {
  const { server, socketPath } = await fixture(t);
  const connected = connectedSocket(server);
  const waiting = waitForStream(
    socketPath,
    "song",
    new AbortController().signal,
  );
  const socket = await connected;
  socket.write(
    [
      { event: "property-change", name: "path", data: "old-song" },
      { event: "property-change", name: "track-list", data: [] },
      { event: "property-change", name: "idle-active", data: false },
      { event: "file-loaded" },
      { request_id: 11, error: "success", data: [{ id: 9 }] },
      { request_id: 12, error: "success", data: false },
      { request_id: 10, error: "success", data: "song" },
    ]
      .map((message) => JSON.stringify(message))
      .join("\n") + "\n",
  );
  assert.deepEqual(await waiting, { stream: "song", tracks: [{ id: 9 }] });
});

void test("connection waits for the owner's IPC startup completion", async (t) => {
  const { server, socketPath } = await fixture(t, false);
  const connected = connectedSocket(server);
  const waiting = waitForStream(
    socketPath,
    "song",
    new AbortController().signal,
  );
  setIpcReady(true);
  const socket = await connected;
  socket.write(
    [
      { event: "property-change", name: "path", data: "song" },
      { event: "property-change", name: "track-list", data: [] },
      { event: "property-change", name: "idle-active", data: false },
    ]
      .map((message) => JSON.stringify(message))
      .join("\n") + "\n",
  );
  assert.deepEqual(await waiting, { stream: "song", tracks: [] });
});

void test("an old child exit cannot invalidate its replacement's readiness", async (t) => {
  const { server, socketPath } = await fixture(t);
  const previous = setIpcReady(false);
  const current = setIpcReady(false);
  setIpcReady(true, current);
  setIpcReady(false, previous);
  const connected = connectedSocket(server);
  const waiting = waitForStream(
    socketPath,
    "song",
    new AbortController().signal,
    1000,
  );
  const socket = await connected;
  socket.write(
    [
      { event: "property-change", name: "path", data: "song" },
      { event: "property-change", name: "track-list", data: [] },
      { event: "property-change", name: "idle-active", data: false },
    ]
      .map((message) => JSON.stringify(message))
      .join("\n") + "\n",
  );
  assert.deepEqual(await waiting, { stream: "song", tracks: [] });
});

void test("a newer file-load discards the older snapshot replies", async (t) => {
  const { server, socketPath } = await fixture(t);
  const connected = connectedSocket(server);
  const waiting = waitForStream(
    socketPath,
    "song",
    new AbortController().signal,
  );
  const socket = await connected;
  socket.write(
    [
      { event: "property-change", name: "path", data: "old-song" },
      { event: "property-change", name: "track-list", data: [] },
      { event: "property-change", name: "idle-active", data: false },
      { event: "file-loaded" },
      { event: "file-loaded" },
      { request_id: 10, error: "property unavailable" },
      { request_id: 11, error: "success", data: [{ id: 1 }] },
      { request_id: 12, error: "success", data: false },
      { request_id: 21, error: "success", data: [{ id: 2 }] },
      { request_id: 22, error: "success", data: false },
      { request_id: 20, error: "success", data: "song" },
    ]
      .map((message) => JSON.stringify(message))
      .join("\n") + "\n",
  );
  assert.deepEqual(await waiting, { stream: "song", tracks: [{ id: 2 }] });
});

void test("cancellation closes an idle IPC connection", async (t) => {
  const { server, socketPath } = await fixture(t);
  const connected = connectedSocket(server);
  const controller = new AbortController();
  const waiting = waitForStream(socketPath, "song", controller.signal);
  const rejection = assert.rejects(waiting, { name: "AbortError" });
  const socket = await connected;
  socket.resume();
  const closed = events.once(socket, "close");
  controller.abort();
  await rejection;
  await closed;
});

void test("one deadline bounds an absent IPC socket", async (t) => {
  const { socketPath } = await fixture(t, false);
  await assert.rejects(
    waitForStream(
      socketPath + ".absent",
      undefined,
      new AbortController().signal,
      20,
    ),
    /readiness timeout/,
  );
});
