# Maintainerr

This recipe builds Maintainerr from the immutable `v3.30.1` source tag with
Node.js 26 and the checked-in Yarn lockfile. Nix fetches the Yarn dependency
cache separately, and the sandboxed build has no network access. The build
compiles `better-sqlite3`, `canvas`, and `sharp` against Node 26 and Nixpkgs
libraries, then removes their bundled cross-platform native binaries.
The recipe requires Nixpkgs Node 26.12.0 or newer, which includes the V8 ARM
header fix, and libvips 8.18.7 or newer for `sharp`. It uses those unmodified
Nixpkgs packages and rejects older package sets. Private Vips source and V8
header fallbacks are retired.

Run the service with a writable `DATA_DIR`. The executable stages the web UI
under that directory so it can replace the runtime `BASE_PATH` placeholder,
then starts the server. The default remains `/opt/data`; NixOS services should
set an explicit state directory.

Updates are intentionally manual because each release needs a new source hash,
Yarn cache hash and platform-dependency `missing-hashes.json`, plus review of
upstream's Node requirement, Docker build, native addon dependencies, migrations,
and release notes. Upstream now reads `DATA_DIR` through a shared config module,
so the former local logging-path substitutions are no longer needed. A
successful package build compiles and installs the native addons and
application. Former package-owned addon-loading and service checks are retired;
verify addon loading, startup and readiness manually on the target host.
