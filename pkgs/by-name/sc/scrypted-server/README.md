# Scrypted server

This package compiles the pinned `@scrypted/server` TypeScript source from its
upstream release tag as a native Node.js application. The lockfile comes from
the same tag, with
`node-addon-api` added because `@scrypted/node-pty` uses it when built from
source but omits it from its own dependencies. The package compiles node-pty,
classic-level, and sharp offline, using Nixpkgs libvips for sharp. It removes
their published native binaries and build objects from the output, omits
development dependencies, and skips upstream install scripts
that download Python and FFmpeg. Supply those tools from Nix at runtime using
`SCRYPTED_PYTHON_PATH` and `SCRYPTED_FFMPEG_PATH`.

The reviewed lockfile selects `tar` 7.5.21 for its archive security fixes,
with a package-local `minizlib` 3.1.0 resolution. Other consumers retain
their existing compression dependency. The installed tar package includes its
Blue Oak Model License 1.0.0 notice. Install checks exercise the actual parser,
archive extraction and compiled Scrypted installation method with local fixtures.
A local metadata guard keeps pending PAX fields off intermediary GNU/PAX
headers and truncates GNU names and links at the first NUL, including when
newlines follow it. The build regenerates both CommonJS and ES module bundles from the
patched modules using the upstream flags. Retain this patch until the same
regressions pass against an unmodified upstream release.
The default compression-ratio guard remains enabled; it does not impose an
absolute archive-size or entry-count budget.

The installed server and native addons are built from source. Its Nix source
provenance records that output. Scrypted
plugins, accounts, and device settings belong in a writable state directory;
the server package itself is immutable. Upstream plugins may fetch additional
packages when installed through the Scrypted UI.

To update, change the release and GitHub source hash in `source.nix`, copy the
matching `server/package-lock.json` from the release tag, add the missing
`node-addon-api` dependency to its lockfile, retain the reviewed tar security resolution until
upstream supplies an equally patched version, update `npmDepsHash`, and build
on both x86_64 Linux and aarch64 Linux. Review new install scripts and native
dependencies before deploying.
