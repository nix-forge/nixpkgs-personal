# SoundCraft

Source build of [SoundCraft 0.7.0](https://github.com/storytold/soundcraft/releases/tag/v0.7.0) at `3a28a657692c1b98b28c276d8f61df9471074f0f`.
Installs `soundcraft` and `soundcraft-cli`, retaining the default automation/plugin capabilities.

Linux includes X11/Wayland and Vulkan/OpenGL loader paths, desktop entries, icons and available MIME definitions. macOS includes a native app bundle with upstream document declarations and an ad-hoc signature. The CLI remains independently invocable. Browser/WASM targets and developer xtask are not desktop deliverables.

The build runs native workspace library tests and installed CLI/desktop checks. Separate package checks exercise document exports and GUI startup. Tests needing external corpora, optional models, services or physical devices need separate upstream integration runs. See [the packaging research and validation record](../../../../docs/artcraft-packaging-research.md) for completed checks and platform limits.

The public flake exports x86_64-linux, aarch64-linux and aarch64-darwin. For Intel macOS, call this independent recipe with `pkgs.callPackage ./package.nix { }` from a Nixpkgs 26.05 instance providing Rust 1.95 or newer. Nixpkgs 26.11 dropped Intel Darwin support, so the current public flake and its overlay do not expose that system.

Updates are manual: inspect an upstream release/commit and its manifests, asset terms and packaging templates; update `source.nix` and its release metadata, review and refresh the checked-in Cargo lock files, recompute immutable source and Git dependency hashes, then rebuild with strict sandboxing. These projects are early alpha with rapidly changing interfaces, so unattended updates are not enabled.

Non-NixOS graphics can require [nixGL](https://github.com/nix-community/nixGL) using the same Nixpkgs pin as this package.

Linux regular and bold symbol fallbacks refer directly to the packaged DejaVu fonts. Source tests check family priority and glyphs for the disclosure arrows, musical sharp and close control independently of host font configuration. The existing `SOUNDCRAFT_NO_SYSTEM_FONTS` override remains available.

On native macOS, `hostTests.native` provides the Apple Audio Units insertion regression. The source build compiles the original test and excludes only its execution inside the sandbox. Build the separate artifact with `nix build .#soundcraft.hostTests.native --option sandbox true --out-link result-native-tests`, then run `./result-native-tests/bin/soundcraft-host-tests` on the host. This retains the hardware/service assertions while keeping ordinary source builds sandboxed.

See the [patch-retirement record](../../../../docs/research/artcraft-patch-retirement-research.md) for this source update. Earlier completed build receipts apply only to their recorded revisions.

The autosave recovery test sets explicit modification times for its older saved
session and newer autosave, avoiding equal filesystem clock ticks. All original
recovery, cleanup and audio assertions and production recovery code are retained.
