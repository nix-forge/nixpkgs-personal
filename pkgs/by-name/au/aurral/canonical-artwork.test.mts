import * as api from "./test-api.mts";
import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import path from "node:path";
import { pathToFileURL } from "node:url";

const toImportSpecifier = (file: string): string => pathToFileURL(file).href;
const app = process.argv[2];
if (!app) throw new Error("Pass the Aurral package root");

const group = "11111111-1111-4111-8111-111111111111";
const canonical = `https://coverartarchive.org/release-group/${group}/front-1200`;
const packaging = "https://example.org/physical-edition.jpg";
const images = new Map([[`rg:${group}`, { imageUrl: packaging }]]);
let available = true;
const rejected = new Set<string>();
let providerCalls = 0;
let warmed: string[] = [];
Reflect.set(globalThis, "artworkFixture", {
  images,
  rejected,
  warm: async (url: string) => {
    warmed.push(url);
    return available ? url : null;
  },
  provider: async () => {
    providerCalls++;
    return { images: [{ kind: "front", url: packaging }] };
  },
});
const fixtures: Record<string, string> = {
  "../db/helpers/index.ts": `const f = globalThis.artworkFixture; export const dbOps = {
    getImage: key => f.images.get(key), setImage: (key, imageUrl) => f.images.set(key, {imageUrl}),
    deleteImage: key => f.images.delete(key),
    getImages: keys => Object.fromEntries(keys.map(k => [k, f.images.get(k)])) };`,
  "./imageProxyService.ts": `export const buildStableImageProxyUrl = x => globalThis.artworkFixture.rejected.has(x) ? null : x;
    export const warmPublicImageUrl = globalThis.artworkFixture.warm;`,
  "./apiClients/deezer.ts": `export const getDeezerArtist = async () => null;
    export const getDeezerArtistById = async () => null;
    export const resolveDeezerAlbumForPreview = async () => null;`,
  "./providers/brainzmashProvider.ts": `export const getAlbumByMbid = globalThis.artworkFixture.provider;
    export const resolveAlbumByArtistAndTitle = async () => null;
    export const isMetadataNotFoundError = error => error?.status === 404;`,
};
const hooks = registerHooks({
  resolve(specifier, context, next) {
    if (
      context.parentURL?.endsWith("/releaseGroupCoverService.ts") &&
      fixtures[specifier]
    )
      return {
        url: `data:text/javascript,${encodeURIComponent(fixtures[specifier])}`,
        shortCircuit: true,
      };
    return next(specifier, context);
  },
});
try {
  const service = await api.load(
    toImportSpecifier(
      path.resolve(app, "backend/services/releaseGroupCoverService.ts"),
    ),
    api.artwork,
  );
  const result = await service.fetchReleaseGroupCoverUrl(group);
  assert.equal(
    result.imageUrl,
    canonical,
    "canonical cover must win over old cached packaging art",
  );
  assert.equal(providerCalls, 0);
  assert.deepEqual(warmed, [canonical]);
  const batch = await service.resolveReleaseGroupCoversBatch([{ mbid: group }]);
  assert.equal(api.present(batch[group]).image, canonical);
  assert.equal(
    api.present(service.attachCachedCoverUrls([{ id: group }])[0]).coverUrl,
    canonical,
  );
  rejected.add(canonical);
  const rejectedProxy = await service.fetchReleaseGroupCoverUrl(group, {
    bypassCache: true,
  });
  assert.equal(
    rejectedProxy.imageUrl,
    packaging,
    "rejected canonical proxy preserves a non-null provider fallback",
  );
  rejected.clear();
  available = false;
  const fallback = await service.fetchReleaseGroupCoverUrl(group, {
    bypassCache: true,
  });
  assert.equal(
    fallback.imageUrl,
    packaging,
    "preserve fallback when the canonical source is unavailable",
  );
  console.log(
    "Canonical artwork selection, cache migration and fallback passed",
  );
} finally {
  hooks.deregister();
  Reflect.deleteProperty(globalThis, "artworkFixture");
}
