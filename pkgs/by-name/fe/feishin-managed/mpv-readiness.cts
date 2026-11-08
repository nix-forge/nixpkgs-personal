import mpvMessage = require("./mpv-message.cjs");
// The player owner reports IPC startup completion. Subscribe before its snapshot
// and use mpv file-loaded/property events under one deadline and cancellation.
import nodeNodeEvents = require("node:events");
const { EventEmitter } = nodeNodeEvents;
import net = require("node:net");
const lifecycle = new EventEmitter();
let ipcReady = false;
let generation = 0;

function setIpcReady(ready: boolean, owner?: number): number {
  if (owner !== undefined && owner !== generation) return generation;
  if (!ready && owner === undefined) generation += 1;
  ipcReady = ready;
  lifecycle.emit("ready", ready);
  return generation;
}

interface MpvState {
  stream: unknown;
  tracks: unknown;
}

function waitForStream(
  socketPath: string,
  expected: string | undefined,
  signal: AbortSignal,
  timeoutMs = 12000,
): Promise<MpvState> {
  return new Promise((resolve, reject) => {
    let socket: import("node:net").Socket | undefined;
    let finished = false;
    let initial = true;
    let requestBase = 0;
    let stream: unknown;
    let tracks: unknown;
    let idle: unknown;
    const received = new Set<string>();
    const cleanup = () => {
      clearTimeout(deadline);
      signal.removeEventListener("abort", cancel);
      lifecycle.off("ready", onReady);
      socket?.destroy();
    };
    const fail = (error: unknown) => {
      if (finished) return;
      finished = true;
      cleanup();
      reject(error);
    };
    const cancel = () => fail(signal.reason);
    const deadline = setTimeout(
      () => fail(new Error("mpv readiness timeout")),
      timeoutMs,
    );
    const inspect = () => {
      if (received.size !== 3) return;
      initial = false;
      if (
        typeof stream !== "string" ||
        (expected && stream !== expected) ||
        idle !== false ||
        !Array.isArray(tracks)
      )
        return;
      finished = true;
      cleanup();
      resolve({ stream, tracks });
    };
    const connect = () => {
      if (finished || socket) return;
      const connection = net.createConnection(socketPath);
      socket = connection;
      let buffer = "";
      connection.on("connect", () => {
        if (finished || socket !== connection) return;
        for (const [index, name] of [
          "path",
          "track-list",
          "idle-active",
        ].entries()) {
          connection.write(
            JSON.stringify({
              command: ["observe_property", index, name],
              request_id: index,
            }) + "\n",
          );
        }
      });
      connection.on("data", (chunk: Buffer) => {
        if (finished || socket !== connection) return;
        buffer += chunk.toString();
        let end: number;
        while ((end = buffer.indexOf("\n")) >= 0) {
          const line = buffer.slice(0, end);
          buffer = buffer.slice(end + 1);
          try {
            const message = mpvMessage.parseMessage(line);
            // Ignore terminal replies from an earlier file-load before inspecting
            // their error: a superseded request may fail during replacement.
            if (
              message.request_id !== undefined &&
              message.request_id >= 10 &&
              (message.request_id < requestBase ||
                message.request_id >= requestBase + 3)
            )
              continue;
            if (message.error && message.error !== "success")
              throw new Error(message.error);
            if (message.event === "file-loaded") {
              initial = false;
              requestBase += 10;
              received.clear();
              for (const [index, name] of [
                "path",
                "track-list",
                "idle-active",
              ].entries()) {
                connection.write(
                  JSON.stringify({
                    command: ["get_property", name],
                    request_id: index + requestBase,
                  }) + "\n",
                );
              }
            }
            const snapshotReply =
              requestBase >= 10 &&
              message.request_id !== undefined &&
              message.request_id >= requestBase &&
              message.request_id < requestBase + 3;
            const name =
              message.event === "property-change"
                ? message.name
                : snapshotReply
                  ? ["path", "track-list", "idle-active"][
                      message.request_id! - requestBase
                    ]
                  : undefined;
            if (!name) continue;
            if (name === "path") {
              if (
                !initial &&
                message.event === "property-change" &&
                stream !== message.data
              )
                received.clear();
              stream = message.data;
            } else if (name === "track-list") tracks = message.data;
            else if (name === "idle-active") idle = message.data;
            // Later path changes are inspected after file-loaded snapshots.
            if (initial || snapshotReply) {
              received.add(name);
              inspect();
            } else {
              // A final idle/track notification can follow the snapshot replies.
              // A changed path clears the snapshot until the next file-loaded.
              inspect();
            }
          } catch (error) {
            fail(error);
            return;
          }
          if (finished) return;
        }
      });
      connection.on("error", (error) => {
        if (socket === connection) fail(error);
      });
      connection.on("close", () => {
        if (!finished && socket === connection)
          fail(new Error("mpv IPC closed before readiness"));
      });
    };
    const onReady = (ready: boolean) => {
      if (ready) {
        connect();
      } else {
        const old = socket;
        socket = undefined;
        old?.destroy();
        received.clear();
        initial = true;
        stream = undefined;
        tracks = undefined;
        idle = undefined;
      }
    };
    signal.addEventListener("abort", cancel, { once: true });
    if (signal.aborted) {
      cancel();
      return;
    }
    lifecycle.on("ready", onReady);
    onReady(ipcReady);
  });
}

export = { waitForStream, setIpcReady };
