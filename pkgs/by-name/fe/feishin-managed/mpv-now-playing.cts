import mpvMessage = require("./mpv-message.cjs");
// Feed Feishin's selected artwork to mpv's macOS Now Playing integration.
// Feishin emits update-song on macOS, but upstream only consumes it on Linux.
interface IpcMain {
  on(
    channel: string,
    listener: (_event: unknown, ...args: unknown[]) => void,
  ): void;
}

interface ElectronAPI {
  app: { getPath(name: "userData"): string };
  ipcMain: IpcMain;
}
function isElectronAPI(value: unknown): value is ElectronAPI {
  if (value === null || typeof value !== "object") return false;
  const app: unknown = Reflect.get(value, "app");
  const ipc: unknown = Reflect.get(value, "ipcMain");
  return (
    app !== null &&
    typeof app === "object" &&
    typeof Reflect.get(app, "getPath") === "function" &&
    ipc !== null &&
    typeof ipc === "object" &&
    typeof Reflect.get(ipc, "on") === "function"
  );
}
const electron: unknown = require("electron");
if (!isElectronAPI(electron)) throw new Error("Electron host API changed");
const { app, ipcMain } = electron;
import nodeNodeCrypto = require("node:crypto");
const { createHash } = nodeNodeCrypto;
import nodeNodeFsPromises = require("node:fs/promises");
const { mkdir, readdir, rm, writeFile } = nodeNodeFsPromises;
import net = require("node:net");
import path = require("node:path");
import localMpvReadinessCjs = require("./mpv-readiness.cjs");
const { waitForStream } = localMpvReadinessCjs;

interface MpvTrack {
  id: number;
  external?: boolean;
  image?: boolean;
  "external-filename"?: string;
}

function isMpvTrack(value: unknown): value is MpvTrack {
  if (
    value === null ||
    typeof value !== "object" ||
    typeof Reflect.get(value, "id") !== "number"
  )
    return false;
  for (const field of ["external", "image"])
    if (
      Reflect.get(value, field) !== undefined &&
      typeof Reflect.get(value, field) !== "boolean"
    )
      return false;
  const filename: unknown = Reflect.get(value, "external-filename");
  return filename === undefined || typeof filename === "string";
}

const MAX_ART_BYTES = 8 * 1024 * 1024;
const socketPath = `/tmp/node-mpv-${process.pid}.sock`;
let revision = 0;
let artworkPath: string | undefined;
let expectedStream: string | undefined;
let artworkTransition = Promise.resolve();
let readiness = new AbortController();

function mpvCommand(command: readonly (string | number)[]): Promise<unknown> {
  return new Promise<unknown>((resolve, reject) => {
    const socket = net.createConnection(socketPath);
    const timeout = setTimeout(
      () => socket.destroy(new Error("mpv IPC timeout")),
      1500,
    );
    let buffer = "";
    let answered = false;
    socket.on("connect", () =>
      socket.write(JSON.stringify({ command, request_id: 1 }) + "\n"),
    );
    socket.on("data", (chunk: Buffer) => {
      buffer += chunk.toString();
      let end: number;
      while ((end = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, end);
        buffer = buffer.slice(end + 1);
        try {
          const answer = mpvMessage.parseMessage(line);
          if (answer.request_id !== 1) continue;
          if (answer.error !== "success") throw new Error(answer.error);
          answered = true;
          clearTimeout(timeout);
          socket.end();
          resolve(answer.data);
          return;
        } catch (error) {
          socket.destroy();
          reject(error);
          return;
        }
      }
    });
    socket.on("error", reject);
    socket.on("close", () => {
      clearTimeout(timeout);
      if (!answered) reject(new Error("mpv IPC closed before replying"));
    });
  });
}

async function fetchArtwork(
  url: string,
  id: number,
): Promise<string | undefined> {
  const parsed = new URL(url);
  if (!["http:", "https:"].includes(parsed.protocol)) return undefined;
  const response = await fetch(parsed, { signal: AbortSignal.timeout(10000) });
  if (
    !response.ok ||
    !response.body ||
    Number(response.headers.get("content-length") || 0) > MAX_ART_BYTES
  )
    return undefined;
  const chunks: Uint8Array[] = [];
  let size = 0;
  for await (const chunk of response.body) {
    size += chunk.length;
    if (size > MAX_ART_BYTES || id !== revision) {
      await response.body.cancel().catch(() => {});
      return undefined;
    }
    chunks.push(chunk);
  }
  const bytes = Buffer.concat(chunks);
  if (id !== revision) return undefined;
  const format = bytes.subarray(0, 3).equals(Buffer.from([0xff, 0xd8, 0xff]))
    ? "jpg"
    : bytes
          .subarray(0, 8)
          .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
      ? "png"
      : bytes.toString("ascii", 0, 4) === "RIFF" &&
          bytes.toString("ascii", 8, 12) === "WEBP"
        ? "webp"
        : undefined;
  if (!format) return undefined;
  const directory = path.join(app.getPath("userData"), "now-playing-artwork");
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const filename = `${createHash("sha256").update(bytes).digest("hex")}.${format}`;
  const target = path.join(directory, filename);
  await writeFile(target, bytes, { mode: 0o600 });
  if (id !== revision) return undefined;
  for (const old of await readdir(directory)) {
    if (old !== filename) await rm(path.join(directory, old), { force: true });
  }
  return target;
}

async function applyArtwork(id: number, signal: AbortSignal): Promise<void> {
  if (id !== revision || signal.aborted) return;
  const state = await waitForStream(socketPath, expectedStream, signal);
  if (id !== revision || signal.aborted) return;
  if (!Array.isArray(state.tracks) || !state.tracks.every(isMpvTrack))
    throw new Error("Invalid mpv track list");
  const external = state.tracks.filter(
    (track: MpvTrack) => track.external && track.image,
  );
  for (const track of external) {
    if (id !== revision || signal.aborted) return;
    if (track["external-filename"] !== artworkPath)
      await mpvCommand(["video-remove", track.id]);
  }
  if (id !== revision || signal.aborted) return;
  if (
    artworkPath &&
    !external.some(
      (track: MpvTrack) => track["external-filename"] === artworkPath,
    )
  )
    await mpvCommand(["video-add", artworkPath, "auto"]);
}

function scheduleArtwork(id: number): void {
  readiness.abort();
  readiness = new AbortController();
  const signal = readiness.signal;
  artworkTransition = artworkTransition
    .then(() => applyArtwork(id, signal))
    .catch(() => {});
}

function install(): void {
  ipcMain.on("player-set-queue", (_event, current) => {
    expectedStream = typeof current === "string" ? current : undefined;
    if (artworkPath) scheduleArtwork(revision);
  });
  ipcMain.on("player-auto-next", () => {
    expectedStream = undefined;
    if (artworkPath) scheduleArtwork(revision);
  });
  ipcMain.on("update-song", (_event, song, url) => {
    const id = ++revision;
    artworkPath = undefined;
    if (!song || typeof url !== "string" || !url) {
      scheduleArtwork(id);
      return;
    }
    void fetchArtwork(url, id)
      .then((result) => {
        if (id !== revision) return;
        artworkPath = result;
        scheduleArtwork(id);
      })
      .catch(() => {});
  });
}

export = { install };
