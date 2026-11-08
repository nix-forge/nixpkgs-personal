import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

// Exercise the packaged IPC handlers together. A temporary audio-device probe
// must never replace or unlink the socket belonging to the playback child.
function player({ deviceQueryHangs = false, stopHangs = false } = {}) {
  const mainPath = process.env["FEISHIN_MAIN"];
  assert.ok(mainPath, "FEISHIN_MAIN is required");
  const main = readFileSync(mainPath, "utf8");
  const start = main.indexOf("let mpvInstance = null;");
  const end = main.indexOf("let mpvState = 0;", start);
  assert.ok(start >= 0 && end > start);
  const handlers = new Map<
    string,
    (event: null, ...args: unknown[]) => unknown
  >();
  const children: Mpv[] = [];
  const events: unknown[][] = [];
  let socketOwner: Mpv | undefined;
  class Mpv extends EventEmitter {
    running = false;
    mpvPlayer: EventEmitter & {
      exitCode: number | null;
      signalCode: NodeJS.Signals | null;
      kill(): void;
    };
    constructor() {
      super();
      this.mpvPlayer = Object.assign(new EventEmitter(), {
        exitCode: null as number | null,
        signalCode: null as NodeJS.Signals | null,
        kill: () => this.exit(),
      });
      children.push(this);
    }
    async start() {
      await new Promise<void>((resolve) => setImmediate(resolve));
      // oxlint-disable-next-line typescript/no-this-alias -- model ownership of the mocked IPC socket.
      socketOwner = this;
      this.running = true;
    }
    exit() {
      this.running = false;
      this.mpvPlayer.exitCode = 0;
      this.mpvPlayer.emit("exit");
    }
    async quit() {
      // node-mpv acknowledges quit before the OS child exits.
      setImmediate(() => this.exit());
    }
    isRunning() {
      return this.running;
    }
    async setMultipleProperties() {}
    async getProperty() {
      if (deviceQueryHangs) return new Promise<never>(() => {});
      return [{ name: "auto", description: "Default" }];
    }
    async stop(): Promise<void> {
      if (stopHangs) await new Promise<never>(() => {});
    }
    async load() {
      assert.equal(
        socketOwner,
        this,
        "playback IPC socket was replaced or unlinked",
      );
      this.emit("timeposition", 1);
    }
  }
  const context = vm.createContext({
    MpvAPI: Mpv,
    uniq: <T,>(values: T[]) => [...new Set(values)],
    node_process: { pid: 123 },
    isWindows: () => false,
    isMacOS: () => false,
    store: { get: () => undefined },
    promises: {
      rm: async () => {
        socketOwner = undefined;
      },
      access: async () => {},
    },
    log: { info() {}, warn() {}, error() {}, debug() {} },
    sendToastToRenderer() {},
    getMainWindow: () => ({
      webContents: { send: (...args: unknown[]) => events.push(args) },
    }),
    require: () => ({
      configurePlayer() {},
      setIpcReady(ready: boolean) {
        events.push(["ipc-ready", ready]);
      },
      join: () => "",
      app: { getPath: () => "" },
    }),
    require$$0: {
      ipcMain: {
        handle: (
          name: string,
          callback: (event: null, ...args: unknown[]) => unknown,
        ) => handlers.set(name, callback),
        on: (
          name: string,
          callback: (event: null, ...args: unknown[]) => unknown,
        ) => handlers.set(name, callback),
      },
    },
    setTimeout: (callback: () => void, delay: number) => {
      return setTimeout(callback, Math.min(delay, 30));
    },
    clearTimeout,
  });
  vm.runInContext(main.slice(start, end), context);
  return {
    call: (name: string, ...args: unknown[]) => {
      const handler = handlers.get(name);
      assert.ok(handler, `Missing IPC handler: ${name}`);
      return handler(null, ...args);
    },
    children,
    events,
    current: () => {
      const current: unknown = vm.runInContext("getMpvInstance()", context);
      assert.ok(current instanceof Mpv, "Missing playback instance");
      return current;
    },
  };
}

await test("audio-device discovery and initialization leave one usable playback child", async () => {
  const p = player();
  await Promise.all([
    p.call("player-get-audio-devices"),
    p.call("player-initialize", {}),
  ]);
  await p.current().load();
  assert.equal(p.children.filter((child) => child.isRunning()).length, 1);
  assert.ok(
    p.events.some(([event]) => event === "renderer-player-current-time"),
  );
});

await test("quit and initialization cannot erase the replacement player", async () => {
  const p = player();
  await p.call("player-initialize", {});
  await Promise.all([p.call("player-quit"), p.call("player-initialize", {})]);
  assert.ok(p.current()?.isRunning(), "replacement playback child is missing");
  await p.current().load();
  assert.equal(p.children.filter((child) => child.isRunning()).length, 1);
});

await test("device discovery on a running player preserves its playback events", async () => {
  const p = player();
  await p.call("player-initialize", {});
  await p.call("player-get-audio-devices");
  await p.current().load();
  assert.equal(p.children.length, 1);
  assert.ok(
    p.events.some(([event]) => event === "renderer-player-current-time"),
  );
});

await test("initialization followed by device discovery reuses the playback child", async () => {
  const p = player();
  await Promise.all([
    p.call("player-initialize", {}),
    p.call("player-get-audio-devices"),
  ]);
  await p.current().load();
  assert.equal(p.children.length, 1);
});

await test("device discovery during restart leaves the replacement socket usable", async () => {
  const p = player();
  await p.call("player-initialize", {});
  await Promise.all([
    p.call("player-restart", {}),
    p.call("player-get-audio-devices"),
  ]);
  await p.current().load();
  assert.equal(p.children.filter((child) => child.isRunning()).length, 1);
});

await test(
  "stalled audio-device discovery releases the lifecycle queue",
  { timeout: 1000 },
  async () => {
    const p = player({ deviceQueryHangs: true });
    await p.call("player-get-audio-devices");
    await p.call("player-initialize", {});
    await p.current().load();
    assert.equal(p.children.filter((child) => child.isRunning()).length, 1);
  },
);

await test(
  "quit reaches its bounded fallback without waiting for a stalled stop command",
  { timeout: 1000 },
  async () => {
    const p = player({ stopHangs: true });
    await p.call("player-initialize", {});
    await p.call("player-quit");
    await p.call("player-initialize", {});
    await p.current().load();
  },
);
