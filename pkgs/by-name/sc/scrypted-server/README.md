# Scrypted server

This package compiles the pinned `@scrypted/server` TypeScript source from its
upstream release tag as a native Node.js application. The lockfile comes from
the same tag, with the reviewed dependency selections in
`dependency-policy.json`. That policy also supplies `node-addon-api`, which
`@scrypted/node-pty` uses when built from source but omits from its dependencies. The package compiles node-pty,
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

The dependency policy pins the reviewed parser, proxy, transport, image and
archive updates. The explicit glob 14 override retains cacache's CommonJS API;
checks exercise cache verification/removal and both module formats' matching
and cancellation. Rimraf is checked before development dependencies are pruned.
The portable Python helper resolves the same patched ZIP implementation.

Sharp 0.35 is built explicitly against Nix libraries. Remove its platform binary
packages while retaining its JavaScript colour dependency. The package-local
libvips variant selects librsvg with the upstream duplicate-entity fix. When
Nixpkgs supplies the reviewed 2.62.3 or 2.63.0, backport commit
[e56cc8a33a7184eef6e8a720414aee6205a400ad](https://gitlab.gnome.org/GNOME/librsvg/-/commit/e56cc8a33a7184eef6e8a720414aee6205a400ad)
without changing Cargo inputs. Its code changes match the 2.63 branch fix
[8a1b0cd319e9af2d1e9cf878081dd77f227a0504](https://gitlab.gnome.org/GNOME/librsvg/-/commit/8a1b0cd319e9af2d1e9cf878081dd77f227a0504)
and apply to both reviewed sources without fuzz. Retire the patch for fixed 2.62.4 or later stable
releases, or 2.63.2 and later. An unexpected intervening version requires review.
Installed SVG rendering verifies the loaded native library path. The small
repeated-entity rendering fixture is a compatibility check, not proof that the
original memory error was reproduced. Existing inherited library build checks
remain unchanged.

Scrypted's loopback proxy policy is preserved. Direct subnet regressions and
ordinary HTTP, polling, WebSocket, archive and image controls exercise the
updated dependencies; they do not establish a live deployment exploit or complete
service-startup acceptance.

The installed server and native addons are built from source. Its Nix source
provenance records that output. Scrypted
plugins, accounts, and device settings belong in a writable state directory;
the server package itself is immutable. Upstream plugins may fetch additional
packages when installed through the Scrypted UI.

To update, change the release and GitHub source hash in `source.nix`, copy the
matching `server/package-lock.json` from the release tag, add the missing
`node-addon-api` dependency through the manifest policy, apply that policy to
`package.json`, refresh the lockfile with scripts disabled, and retain the reviewed
security resolutions until
upstream supplies an equally patched version, update `npmDepsHash`, and build
on both x86_64 Linux and aarch64 Linux. Review new install scripts and native
dependencies before deploying.
