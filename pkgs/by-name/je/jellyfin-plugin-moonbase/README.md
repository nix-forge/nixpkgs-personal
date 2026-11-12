# Jellyfin Moonbase plugin

This package builds the pinned Moonbase release from its .NET plugin source and
builds the matching Moonfin Web client from a separately pinned Flutter source.
The server has a pinned NuGet graph; the web client has a pinned Dart lock and
Git dependency hashes. The package derives `meta.json` from the plugin's
manifest and disables Jellyfin's automatic plugin updates. The host copies the
full payload into Jellyfin's writable plugin directory at service startup.
The web client compiles to WebAssembly with a JavaScript fallback, matching
upstream's release target. The recipe builds the fallback first so the two
large compilers do not overlap, and retains the SQLite WebAssembly asset used
at runtime.

[Flutter's multithreaded WebAssembly rendering](https://docs.flutter.dev/platform-integration/web/wasm)
requires COOP and COEP response headers from the server. The package does not
change Jellyfin's HTTP headers; WebAssembly can run without those headers using
the single-threaded renderer.

Upstream lists Jellyfin 10.10 or newer as supported and documents the
[Moonbase installation](https://github.com/Moonfin-Client/Plugin/wiki/Installation)
and [Seerr integration](https://github.com/Moonfin-Client/Plugin/wiki/Seerr-Setup).
Run `python3 update.py --dry-run` in the development shell to inspect a stable
release, then `python3 update.py` to refresh both source revisions and hashes,
the server NuGet graph, and the web client's Flutter lock and Git hashes. The
updater reads the plugin manifest to select the bundled Moonfin Web version
and refuses an ABI change or ambiguous web version. If a tagged manifest
predates the release entry, it resolves the upstream default branch manifest
(currently master) to a full commit, checks plugin identity and release asset
linkage, and pins that exact manifest file in `source.nix`. Review the new
manifest, licenses, and resulting file inventory; build the combined package
and check Jellyfin plugin loading before adopting the update.
