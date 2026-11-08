# ReactFlux

Static ReactFlux, pinned to an immutable upstream revision with locked pnpm
dependencies. Serve `share/reactflux` with an SPA fallback and proxy `/v1/` to
a compatible Miniflux server. No Node service is needed at runtime.

The package accepts `defaultServerUrl` and `readerDefaults`. These contain public
deployment settings, never credentials. Preferences remain editable in the UI.

Local adaptations remove URL credential login, exchange a website password for
a revocable Miniflux application key, and store only that key in tab session
storage. Closing the browser session requires signing in again. Repeated login
reuses the application key for this origin; revoke it in Miniflux's API key
settings when needed. Logging out clears browser state and does not revoke keys
used by another tab or device.

These are package adaptations for an independently useful frontend, not an
overlay fixing an existing Nixpkgs package. Retire each patch when upstream
provides equivalent deployment defaults and credential handling.

The package runs behavioral authentication and article image tests and checks the installed app,
manifest and service worker. The application is installable as a PWA, but its
upstream worker caches UI assets and fonts, not an offline article library.

Upstream: <https://github.com/electh/ReactFlux>, MIT.

The local media policy uses native HLS playback where the browser supports it.
External HLS streams on other browsers offer a media-player link because the
same-origin API policy does not permit arbitrary JavaScript video fetches.
Missing feed icons use a local fallback. The upstream GitHub update poll is
disabled in production; update the source pin and dependency hash through Nix.

Covers select a supplied `srcset` rendition near 1024 pixels or 2x density,
without rewriting signed or proxied URLs. The reader preserves publisher article
HTML and captions. Its existing image model deduplicates enclosures against
inline images and responsive variants, including variants without declared
image dimensions. WebP and AVIF extensions work when MIME metadata is absent.

Remaining image enclosures appear as visible figures with lightbox controls and
source links. They keep their intrinsic size instead of stretching thumbnails
across the reading column. Failed previews fall back to the attachment list;
audio, video and other files retain their existing handling. Remove these image
adaptations when upstream provides equivalent behavior.

Image checks load the actual prepared-entry and article-image modules, then
server-render the enclosure component with its files panel closed. They cover
responsive signed URLs, unsafe URL fallback, missing MIME types, deduplication,
and visible image figures. They reuse locked application dependencies.

Miniflux's standard signed proxy format is decoded only to compare enclosure
renditions and identify image extensions. Rendering keeps the exact supplied
proxy URL. Custom proxy formats retain their original URL and rely on MIME
metadata or `srcset`. Covers cannot recover detail absent from the publisher's
feed or extracted article; grid thumbnails use natural sizing until a loaded
image is large enough to crop. Browser verification is still needed for
publisher-specific extraction, failed requests and narrow-screen layout.
