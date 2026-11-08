# Aurral

This recipe packages Aurral 2.13.0 from its stable tagged source and frozen pnpm
lockfile. It builds the frontend and native addons in the sandbox. Node 26.13.0
is scoped to this package; the release's Node 26.12 minor engine restriction is
widened to accept its newer release-image runtime. Engine checks stay enabled.
The Node source build uses Clang, matching the official Linux release toolchain;
eight GCC workers exceeded the reviewed daemon working set. The runtime uses a
scoped Brotli 1.2.1 for the decoder API exposed by Node 26.13.

The upstream package manager is pnpm 12.15.0, now a native Rust CLI. The build
uses pinned native pnpm distributions for the build platform, rather than its
JavaScript bootstrap that downloads a binary on first execution. The dependency
fetcher uses portable JSON store indexes; the normal build installs offline with
scripts disabled, then rebuilds bcrypt, better-sqlite3 and Sharp with Nix headers
and tools. Root and workspace dependency links retain pnpm's relative topology.
Honker keeps its upstream native binary. The application wrapper needs no pnpm
or runtime dependency downloads and includes ffmpeg and yt-dlp.

Aurral now uses its native TypeScript recording matcher. The old Python/beets
client is absent upstream, so the package no longer pins beets or sets
AURRAL_MATCHER_PYTHON. The matcher check compares an exact recording and a
contradictory candidate through the actual native matching API.

The service listens on `127.0.0.1:3001` by default. Set `AURRAL_HOST` and `PORT`
for another bind, `AURRAL_DATA_DIR` for writable state, and `DOWNLOAD_FOLDER` for
imported music. A reverse proxy should provide HTTPS.

Set `AURRAL_NAVIDROME_MANAGED_LIBRARY=true` when the host owns Navidrome's library
and scanning. The configured path must match a readable playback library. This
mode verifies Subsonic folder access and leaves administrator library operations
and scan requests to the host; it grants no extra playlist or user access.

## Patch lifecycle, 2.13.0

Review source: [stable 2.13.0](https://github.com/lklynet/aurral/tree/3f01fa586f363f416f2e40c234a95550b87d74f7).
Each retained behavior has a focused package check. The implementation uses the
release's typed services and Hono routes rather than recreating removed APIs.

| Patch | Retained behavior | Superseded implementation and removal condition |
| --- | --- | --- |
| `lidarr-metadata.patch` | Exact imported-file path enrichment, late metadata refresh, stable file-derived identities, six-hour reconciliation, and narrow group-as-release cleanup. | Keep upstream release-aware scan behavior. Remove when upstream provides the same path joining, unchanged-file refresh and persisted-ID migration. |
| `listenbrainz-discover.patch` | Public-username personal recording charts, recent-listen fallback, release-group charts, recommended recordings/playlists, and saving these as static playlists from Discover or Playlists. | Retire the old fallback artist-recommendation and weekly-flow implementations: upstream's musicDataSource and native flow pipeline provide keyless ListenBrainz discovery. Retain only the missing chart adapter and UI, using upstream playlist creation and permission guards. Remove when upstream offers equivalent public-history shelves and save actions. |
| `listenbrainz-connect.patch` | Expected token-owner validation, saved history alignment for ListenBrainz, token redaction, shared cooldown for all request types, and distinct release/group submission IDs. | Retire old Connect dialogs/bootstrap flags. Use the native Listening settings and multiple-provider history model, preserving other providers. Remove when upstream covers the remaining validation, profile and transport guarantees. |
| `native-audio-tags.patch` | Partial dedicated identity updates, legacy migration with dedicated-tag precedence, valid-marker-only clearing, explicit release IDs and preservation of genuine existing releases and file ownership/mode. | Retire the Mutagen implementation. Upstream taglib already writes dedicated Xiph/ID3/MP4 tags on atomic copies and preserves audio and unrelated tags. Remove this reduced delta when upstream covers its remaining update/migration guarantees. |
| `artist-identity.patch` | Promote already enriched name keys, consolidate persisted same-MBID aliases at startup and invalidate Recently Added caches. | Reuse upstream management/star/album/search merge helper; do not duplicate its newer management fields. Remove when upstream repairs enriched keys and persisted duplicates automatically. Distinct MBIDs must remain separate. |
| `canonical-artwork.patch` | Release-group CAA front-first selection, new selection/proxy cache keys, 1200px quality90 proxies, aspect-ratio preservation and no enlargement. | Upstream already prefers Deezer XL images. Remove after equivalent canonical selection and cache migration; provider fallback remains available. |
| `navidrome-managed-library.patch` | Playback-account folder verification, host-owned scan suppression and song-cache invalidation. | Port to upstream ensureAurralLibrary and current song-cache API. Remove when upstream supports this library lifecycle. |

The artwork variant also ports upstream cache fixtures to the new cache key and
1200px profile while retaining their failure, fallback, coalescing and migration
assertions. Both legacy library bytes and the current profile survive cache
migration; rejected canonical proxy links continue to provider fallback.

The build runs upstream's typecheck and complete unit suite before installation.
Package install checks cover generated FLAC/MP3/MP4 audio hashes and tags,
identity/metadata migrations, provider mocks, token/account validation, status
redaction, request throttling, artwork fallback/cache selection and managed
Navidrome access. They use isolated state and no live provider credentials.

Build with `nix build .#aurral` and run repository-required `just check`. Update
the source and pnpm cache hashes together. Review the release's Node and package
manager declarations, native modules, source API changes and this table before
updating. There is no unattended updater because these compatibility decisions
cannot be derived from a release tag.
