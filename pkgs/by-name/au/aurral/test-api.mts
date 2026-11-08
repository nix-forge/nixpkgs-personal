/** Contracts for the selected upstream Aurral APIs exercised by package tests.
 * Dynamic imports cross a JavaScript boundary: validate each export before use.
 * Signatures follow the packaged backend; behavioral assertions verify results.
 */
import assert from "node:assert/strict";
import type { Server } from "node:http";

export function record(value: unknown): Record<string, unknown> {
  assert.ok(isRecord(value), "Expected an object");
  return value;
}
export function array(value: unknown): unknown[] {
  assert.ok(Array.isArray(value), "Expected an array");
  return value;
}
export function string(value: unknown): string {
  assert.equal(typeof value, "string", "Expected a string");
  assert.ok(typeof value === "string");
  return value;
}
export function present<T>(value: T | null | undefined): T {
  assert.ok(value !== undefined && value !== null, "Expected a value");
  return value;
}
export async function load<T>(
  specifier: string,
  validate: (value: unknown) => value is T,
): Promise<T> {
  const module: unknown = await import(specifier);
  assert.ok(validate(module), `Unexpected upstream API: ${specifier}`);
  return module;
}
function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function methods(value: unknown, names: string[]): boolean {
  return (
    (isRecord(value) || typeof value === "function") &&
    names.every((name) => typeof Reflect.get(value, name) === "function")
  );
}
interface Row {
  [key: string]: unknown;
}
interface Database {
  prepare(sql: string): {
    run(...parameters: unknown[]): { lastInsertRowid: number | bigint };
    get(...parameters: unknown[]): Row | undefined;
  };
  close(): void;
}
export function database(value: unknown): value is { db: Database } {
  return isRecord(value) && methods(value["db"], ["prepare", "close"]);
}
export function honker(value: unknown): value is {
  closeHonkerDb(this: void): void;
  SCHEDULED_SYSTEM_TASKS: { name: string; schedule: string }[];
} {
  return (
    methods(value, ["closeHonkerDb"]) &&
    isRecord(value) &&
    Array.isArray(value["SCHEDULED_SYSTEM_TASKS"]) &&
    value["SCHEDULED_SYSTEM_TASKS"].every(
      (task: unknown) =>
        isRecord(task) &&
        typeof task["name"] === "string" &&
        typeof task["schedule"] === "string",
    )
  );
}
interface User {
  id: number;
  listenHistoryProvider?: string;
  listenHistoryUsername?: string | null;
}
interface UserOps {
  createUser(username: string, passwordHash: string, role: string): User;
  updateUser(
    id: number,
    update: {
      listenHistoryProvider: string;
      listenHistoryUsername: string | null;
    },
  ): void;
  getUserById(id: number): User | undefined;
}
export function users(value: unknown): value is { userOps: UserOps } {
  return (
    isRecord(value) &&
    methods(value["userOps"], ["createUser", "updateUser", "getUserById"])
  );
}
export function password(
  value: unknown,
): value is { hashPassword(this: void, password: string): string } {
  return methods(value, ["hashPassword"]);
}
export function mediaStore(value: unknown): value is {
  upsertLibraryArtist(
    this: void,
    input: {
      identityKey: string;
      mbid: string;
      name: string;
    },
  ): { id: number };
  upsertLibraryAlbum(
    this: void,
    input: {
      identityKey: string;
      artistId: number;
      title: string;
    },
  ): { id: number };
  repairLibraryArtistIdentities(this: void): void;
} {
  return methods(value, [
    "upsertLibraryArtist",
    "upsertLibraryAlbum",
    "repairLibraryArtistIdentities",
  ]);
}
export function management(value: unknown): value is {
  getManagedBy(this: void, kind: string, id: number): string | null;
} {
  return methods(value, ["getManagedBy"]);
}
interface AudioMetadata {
  common: {
    grouping?: string;
    musicbrainz_albumid?: string;
    musicbrainz_artistid?: string[];
    musicbrainz_releasegroupid?: string;
    musicbrainz_recordingid?: string;
    title?: string;
    album?: string;
  };
  native: unknown;
}
export function audioParser(
  value: unknown,
): value is { parseFile(this: void, file: string): Promise<AudioMetadata> } {
  return methods(value, ["parseFile"]);
}
export function audioWriter(value: unknown): value is {
  writeAudioMetadata(
    this: void,
    file: string,
    metadata: {
      artistName?: string;
      albumName?: string;
      trackName?: string;
      artistMbid?: string;
      albumMbid?: string;
      trackMbid?: string;
      releaseMbid?: string;
    },
  ): Promise<void>;
  readNativeAurralIdentity(
    this: void,
    metadata: AudioMetadata,
  ): { artistMbid?: string };
} {
  return methods(value, ["writeAudioMetadata", "readNativeAurralIdentity"]);
}
export function fileScanner(value: unknown): value is {
  scanMusicRoot(
    this: void,
    options: {
      rootPath: string;
      source: string;
      force?: boolean;
      metadataReader(): Promise<unknown>;
      metadataEnricher: ((source: unknown, file: string) => unknown) | null;
      metadataLookup: ((path: string) => unknown) | null;
    },
  ): Promise<unknown>;
} {
  return methods(value, ["scanMusicRoot"]);
}
export function indexService(value: unknown): value is {
  getLidarrMetadataByPath(
    this: void,
    client: {
      isConfigured(): boolean;
      getArtists(options: { forceRefresh: boolean }): Promise<unknown>;
      getAllAlbums(options: { forceRefresh: boolean }): Promise<unknown>;
      getAllTracks(): Promise<unknown>;
      getTrackFilesByIds(): Promise<unknown>;
    },
    options: { forceRefresh: boolean },
  ): Promise<Map<string, { albumMbid?: string }>>;
} {
  return methods(value, ["getLidarrMetadataByPath"]);
}
export function systemWorker(value: unknown): value is {
  processSystemTask(this: void, task: { kind: string }): Promise<unknown>;
} {
  return methods(value, ["processSystemTask"]);
}
export function scanWorker(value: unknown): value is {
  getScheduledLibraryScanJobId(this: void): number;
  stopLibraryScanWorker(this: void): Promise<void>;
} {
  return methods(value, [
    "getScheduledLibraryScanJobId",
    "stopLibraryScanWorker",
  ]);
}
interface Track {
  artistName: string;
  trackName: string;
  listenCount: number;
  albumMbid: string | null;
  releaseMbid: string | null;
  coverUrl: string | null;
}
interface Album {
  name: string;
  listenCount: number;
  coverUrl: string | null;
}
interface Artist {
  id: string;
  name: string;
  genres?: string[];
  popularityRank?: number;
  scoreTagAffinity?: number;
}
interface Profile {
  listenHistoryProvider: string;
  listenHistoryUsername: string;
}
interface ChartsOptions {
  count?: number;
  recommendedArtists?: Artist[];
  request(url: string, params: Record<string, unknown>): Promise<unknown>;
}
export function charts(value: unknown): value is {
  getListenbrainzRecordingCharts(
    this: void,
    profile: Profile,
    options: ChartsOptions,
  ): Promise<{
    global: Track[];
    personal: Track[];
    trendingAlbums: Album[];
    recommendedTracks: Track[];
    personalRange: string;
    unavailable: boolean;
    recommendedSource: string;
  }>;
  getListenbrainzRecommendedPlaylists(
    this: void,
    profile: Profile,
    options: Pick<ChartsOptions, "request">,
  ): Promise<{ name: string; tracks: Track[] }[]>;
  normalizeRecording(this: void, input: unknown): Track | null;
  normalizeReleaseGroup(this: void, input: unknown): Album | null;
  coverForRelease(this: void, id: string): string | null;
} {
  return methods(value, [
    "getListenbrainzRecordingCharts",
    "getListenbrainzRecommendedPlaylists",
    "normalizeRecording",
    "normalizeReleaseGroup",
    "coverForRelease",
  ]);
}
export function discovery(value: unknown): value is {
  recommendArtistsFromListenbrainzHistory(
    this: void,
    options: {
      historyArtists: { mbid: string; artistName: string; playcount: number }[];
      getGenres(): Promise<string[]>;
      fallbackGenrePools: Record<string, Artist[]>;
    },
  ): Promise<Artist[]>;
} {
  return methods(value, ["recommendArtistsFromListenbrainzHistory"]);
}
export function recommendations(value: unknown): value is {
  mergeRetainedRecommendationPool(
    this: void,
    options: {
      freshRecommendations: Artist[];
      runStartedAt: string;
    },
  ): Artist[];
} {
  return methods(value, ["mergeRetainedRecommendationPool"]);
}
export function artwork(value: unknown): value is {
  fetchReleaseGroupCoverUrl(
    this: void,
    id: string,
    options?: { bypassCache: boolean },
  ): Promise<{ imageUrl: string | null }>;
  resolveReleaseGroupCoversBatch(
    this: void,
    albums: { mbid: string }[],
  ): Promise<Record<string, { image: string | null }>>;
  attachCachedCoverUrls(
    this: void,
    albums: { id: string }[],
  ): { coverUrl: string | null }[];
} {
  return methods(value, [
    "fetchReleaseGroupCoverUrl",
    "resolveReleaseGroupCoversBatch",
    "attachCachedCoverUrls",
  ]);
}
interface AuthRequest {
  headers?: Record<string, string>;
  user?: unknown;
}
type Middleware = (
  request: AuthRequest,
  response: unknown,
  next: () => void,
) => void;
interface Express {
  (): {
    use(...handlers: (string | Middleware)[]): void;
    listen(port: number, address: string): Server;
  };
  json(): Middleware;
}
export function expressModule(value: unknown): value is { default: Express } {
  return (
    isRecord(value) &&
    typeof value["default"] === "function" &&
    methods(value["default"], ["json"])
  );
}
export function route(value: unknown): value is { default: Middleware } {
  return isRecord(value) && typeof value["default"] === "function";
}
export function authentication(
  value: unknown,
): value is { resolveRequestUser(this: void, request: AuthRequest): unknown } {
  return methods(value, ["resolveRequestUser"]);
}
export function listenbrainz(value: unknown): value is {
  listenbrainzSubmit(
    this: void,
    options: {
      token: string;
      event: {
        playedAt: number;
        artist: string;
        title: string;
        albumMbid: string;
        releaseMbid: string;
      };
    },
  ): Promise<unknown>;
  listenbrainzRequest(this: void, path: string): Promise<unknown>;
} {
  return methods(value, ["listenbrainzSubmit", "listenbrainzRequest"]);
}
interface NavidromeClientContract {
  _songsByFile: Map<string, unknown>;
  _nativeRequest(...args: unknown[]): Promise<unknown>;
  request(
    endpoint: string,
    ...args: unknown[]
  ): Promise<Record<string, unknown>>;
  ensureAurralLibrary(path: string): Promise<unknown>;
  scanLibrary(): Promise<unknown>;
  getPlaylistTrackPaths(): Promise<unknown>;
}
export function navidrome(value: unknown): value is {
  NavidromeClient: new (
    url: string,
    user: string,
    password: string,
  ) => NavidromeClientContract;
} {
  return (
    isRecord(value) &&
    typeof value["NavidromeClient"] === "function" &&
    methods(Reflect.get(value["NavidromeClient"], "prototype"), [
      "request",
      "ensureAurralLibrary",
      "scanLibrary",
      "getPlaylistTrackPaths",
    ])
  );
}
export function matcherRuntime(value: unknown): value is {
  runMatcherOperation(
    this: void,
    operation: string,
    payload: Record<string, unknown>,
    options: { pythonPath: string },
  ): Promise<unknown>;
  verifyMatcherRuntime(
    this: void,
    options: { pythonPath: string },
  ): Promise<{
    available: boolean;
    beetsVersion: string | null;
    protocolVersion: number | null;
    error: unknown;
  }>;
} {
  return methods(value, ["verifyMatcherRuntime", "runMatcherOperation"]);
}

interface HonoContext {
  req: { raw: Request };
  set(key: string, value: unknown): void;
}
interface HonoRouter {
  use(
    handler: (context: HonoContext, next: () => Promise<void>) => Promise<void>,
  ): void;
  route(path: string, router: HonoRouter): void;
  request(url: string, options?: RequestInit): Response | Promise<Response>;
}
export function honoModule(
  value: unknown,
): value is { Hono: new () => unknown } {
  return isRecord(value) && typeof value["Hono"] === "function";
}
export function honoRouter(value: unknown): value is HonoRouter {
  return methods(value, ["use", "route", "request"]);
}
export function honoRoute(value: unknown): value is { default: HonoRouter } {
  return isRecord(value) && honoRouter(value["default"]);
}
export function listeningHistory(value: unknown): value is {
  getListenHistory(
    this: void,
    userId: number,
  ): { listenbrainz: string | null; lastfm: string | null };
  updateListenHistory(
    this: void,
    userId: number,
    sources: { listenbrainz?: string | null; lastfm?: string | null },
  ): unknown;
} {
  return methods(value, ["getListenHistory", "updateListenHistory"]);
}
interface MatcherRecording {
  title: string;
  artists: string[];
  durationMs: number;
}
export function nativeMatcher(value: unknown): value is {
  getMatcherStatus(this: void): { available: boolean };
  decideRecording(
    this: void,
    requested: MatcherRecording,
    candidates: MatcherRecording[],
  ): { decision: string; selectedIndex: number | null };
} {
  return methods(value, ["getMatcherStatus", "decideRecording"]);
}
