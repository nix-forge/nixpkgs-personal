# Craft Launcher

Source-built desktop launcher for the thirteen Craft creative and office apps.
The default WGPU, accessibility, native tray, persistence, X11 and Wayland
features remain enabled. This package installs `craft-launcher`, including
`--version`, and a signed `Craft Launcher.app` on macOS. It is a modified
community distribution with a neutral icon; upstream's restricted ArtCraft
graphical marks are removed.

Tray dependencies retain Linux's `ksni` backend and the native macOS/Windows
backends. Unused GTK defaults are disabled on every target so Cargo's combined
lockfile excludes the affected `glib` graph described in
[GHSA-wrw7-89jp-8q8g](https://github.com/advisories/GHSA-wrw7-89jp-8q8g).
The lock update removes unused dependencies without upgrading retained versions.

Nix-managed apps are discovered through profiles and macOS application bundles.
The launcher opens them but refuses to update or remove them, and disables its
own self-update in the Nix store. Update these packages through your Nix
configuration. Other installations retain upstream management. On Linux,
launcher-downloaded AppImages and their desktop entries use `appimage-run`.
Autostart uses the installed wrapper so its runtime dependencies remain available.

Chinese and Japanese UI use pinned Noto Sans CJK SC and JP fonts, with upstream
platform fallbacks retained. Required source tests cover Japanese catalog glyphs
and baseline alignment. Font and image notices accompany the application and its vendored
Rust dependencies. Ordinary builds and tests do not download application releases.
Runtime release lookup and explicitly requested downloads require network access.

Workspace library and native binary tests exclude browser/WASM and developer
`xtask` targets. They retain debug assertions, synthetic local-server tests,
restart tests and Nix-specific ownership, desktop quoting and font regressions.
Narrow upstream patches preserve state and unrelated update backups, avoid
macOS quit crashes, and preserve customized AppImage desktop entries.
The upstream Pacman detection fix is already included in this release. The
`tests.quitState` check runs the pinned quit library's original close, cancellation
and minimized-window regressions with an injected callback.
Five macOS tests require Apple disk-image/signing services or process inspection.
They run explicitly outside the sandbox using the source-built
`hostTests.native` artifact; their assertions remain intact and their bundles
are confined to temporary directories. Ordinary Darwin tests exclude just these
five host-service tests. Install checks validate the executable, notices and platform integration. The
`tests.cli` passthru checks the installed version and icon aliases. On Linux,
`tests.appstream` validates the installed metadata offline. The Linux desktop ID
is `io.github.nix_forge.craft-launcher`; existing autostart entries retain their
filenames and icon aliases. The macOS bundle identifier remains
`io.github.nix-forge.craft-launcher`.

Copy this directory and use upstream Nixpkgs `callPackage ./package.nix { }`.
Metadata supports x86_64 and aarch64 Linux and macOS. Recent Nixpkgs drops Intel
macOS; use a compatible Nixpkgs such as 26.05 for that platform. ARM Linux source builds use the desktop cross builder. Cross compilation does
not execute target tests; native ARM runtime validation requires a native ARM worker. See the repository's [research](../../../../docs/artcraft-packaging-research.md)
for completed checks and their limits.

Updates are manual. Review the immutable source pin, checked-in Cargo lock and dependency hashes, licensing,
feature defaults, source patches, fonts and bundle/runtime checks together.
