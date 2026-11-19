# Craft Launcher

Source build of [Craft Launcher 0.19.2](https://github.com/storytold/craft-launcher/releases/tag/v0.19.2),
revision `9f950e01ef728a3d32d997d59607051dee98a51d`, for the Craft creative
and office apps.
The default WGPU, accessibility, native tray, persistence, X11 and Wayland
features remain enabled. This package installs `craft-launcher`, including
`--version`, and a signed `Craft Launcher.app` on macOS. It is a modified
community distribution with a neutral icon; upstream's restricted ArtCraft
graphical marks are removed.

Upstream uses Linux's `ksni` tray backend and the native macOS and Windows
backends. Its locked dependencies include Rustls 0.23.46 and retain the
platform's TLS backends.

Nix-managed apps are discovered through profiles and macOS application bundles.
The launcher opens them but refuses to update or remove them, and disables its
own self-update in the Nix store. Update these packages through your Nix
configuration. Other installations retain upstream management. On Linux,
launcher-downloaded AppImages and their desktop entries use `appimage-run`.
Autostart uses the installed wrapper so its runtime dependencies remain available.

The UI bundles Noto fonts for Simplified Chinese, Traditional Chinese,
Japanese, and Georgian alongside upstream platform fallbacks. The source tests
check catalog coverage and baseline alignment. The package includes font, image,
and vendored Rust dependency notices. Ordinary builds and tests do not download application releases.
Runtime release lookup and explicitly requested downloads require network access.

Workspace library and native binary tests exclude browser/WASM and developer
`xtask` targets. They retain debug assertions, synthetic local-server tests,
restart tests and Nix-specific ownership, desktop quoting and font regressions.
The release includes the state and backup handling, autostart quoting, and
macOS quit fixes. The package preserves customized AppImage desktop entries.
Ordinary Darwin builds skip five upstream tests that require Apple disk-image
or signing services or process inspection. The Linux desktop ID
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
