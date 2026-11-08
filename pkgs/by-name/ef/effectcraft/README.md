# EffectCraft

Source build of [EffectCraft 0.10.0](https://github.com/storytold/effectcraft/releases/tag/v0.10.0) at `05955c08b4fd025f1a09882df72e6dbff1a8148a`.
Installs `effectcraft` and `effectcraft-cli`, retaining the default automation/plugin capabilities.
Restricted ArtCraft logo artwork is replaced with plain text; app icons, file types and functionality remain from upstream.

Linux includes X11/Wayland and Vulkan/OpenGL loader paths, desktop entries, icons and available MIME definitions. macOS includes a native app bundle with upstream document declarations and an ad-hoc signature. The CLI remains independently invocable. Browser/WASM targets and developer xtask are not desktop deliverables.

The build runs native workspace library tests and installed CLI/desktop checks. Separate package checks exercise document exports and GUI startup. Tests needing external corpora, optional models, services or physical devices need separate upstream integration runs. See [the packaging research and validation record](../../../../docs/artcraft-packaging-research.md) for completed checks and platform limits.

The public flake exports x86_64-linux, aarch64-linux and aarch64-darwin. For Intel macOS, call this independent recipe with `pkgs.callPackage ./package.nix { }` from a Nixpkgs 26.05 instance providing Rust 1.95 or newer. Nixpkgs 26.11 dropped Intel Darwin support, so the current public flake and its overlay do not expose that system.

The built-in model downloader uses the packaged curl executable on Linux and macOS. Optional Roto/Face weights are installed through the application and are not included in this source package.

Updates are manual: inspect an upstream release/commit and its manifests, asset terms and packaging templates; update `source.nix` and its release metadata, review and refresh the checked-in Cargo lock files, recompute immutable source and Git dependency hashes, then rebuild with strict sandboxing. These projects are early alpha with rapidly changing interfaces, so unattended updates are not enabled.

Non-NixOS graphics can require [nixGL](https://github.com/nix-community/nixGL) using the same Nixpkgs pin as this package.

The macOS font-directory test uses a bundled Inter fixture for discovery and
file-backed loading; Apple system fonts are not exposed to the build sandbox.

Linux font discovery uses the packaged fontconfig executable to include configured font directories. The existing folder fallback remains available when fontconfig fails. Parser and file-backed discovery regressions run in the scoped source suite. This does not implement fontconfig family matching or guarantee all document fonts exist.

See the [patch-retirement record](../../../../docs/research/artcraft-patch-retirement-research.md) for this source update. Earlier completed build receipts apply only to their recorded revisions.

The temporal-offset compatibility patch has been retired after updating the
configured ARM Linux interpreter to QEMU 11.1.2. The unchanged regression at the
selected source revision passes through registered binfmt inside a Nix sandbox
with sandbox fallback disabled. Its original multiplication-overflow failure
reproduces with QEMU 11.1.1 using the identical optimized ARM test executable.
The upstream arithmetic and smoothing regression remain unchanged. This focused
effects-crate check does not establish a complete application build or native
ARM hardware validation. Builders using the affected emulator should update it;
an application arithmetic workaround is unnecessary.
