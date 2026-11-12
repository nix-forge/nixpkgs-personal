# FilmCraft

Source build of [FilmCraft 0.8.0](https://github.com/storytold/filmcraft/releases/tag/v0.8.0) at `f03e21556d8e3a7155b91892d958debd5255d7af`.
Installs `filmcraft` and `filmcraft-cli`, retaining the default automation/plugin capabilities.
CPU Whisper transcription and model downloads are enabled. Models download at runtime on request; no model or service credentials are bundled.
The pinned craft-fonts collection is embedded with required-input checking for multilingual text.
Restricted ArtCraft logo artwork is replaced with plain text; app icons, file types and functionality remain from upstream.

Linux includes X11/Wayland and Vulkan/OpenGL loader paths, desktop entries, icons and available MIME definitions. macOS includes a native app bundle with upstream document declarations and an ad-hoc signature. The CLI remains independently invocable. Browser/WASM targets and developer xtask are not desktop deliverables.

The build runs native workspace library tests and installed CLI/desktop checks. Separate package checks exercise document exports and GUI startup. Tests needing external corpora, optional models, services or physical devices need separate upstream integration runs. See [the packaging research and validation record](../../../../docs/artcraft-packaging-research.md) for completed checks and platform limits.

The public flake exports x86_64-linux, aarch64-linux and aarch64-darwin. For Intel macOS, call this independent recipe with `pkgs.callPackage ./package.nix { }` from a Nixpkgs 26.05 instance providing Rust 1.95 or newer. Nixpkgs 26.11 dropped Intel Darwin support, so the current public flake and its overlay do not expose that system.

Updates are manual: inspect an upstream release/commit and its manifests, asset terms and packaging templates; update `source.nix` and its release metadata, review and refresh the checked-in Cargo locks and font pin, recompute immutable source and Git dependency hashes, then rebuild with strict sandboxing. These projects are early alpha with rapidly changing interfaces, so unattended updates are not enabled.

Non-NixOS graphics can require [nixGL](https://github.com/nix-community/nixGL) using the same Nixpkgs pin as this package.

The macOS font-directory test uses a bundled Inter fixture for discovery and
file-backed loading; Apple system fonts are not exposed to the build sandbox.

FilmCraft’s three buffer-recycling tests share a global reuse counter. A test-only mutex isolates their counter and buffer assertions from parallel test execution; production pooling and every original assertion remain unchanged.

The upstream 24-track mixer speed benchmark now lives in a separate integration
target. Ordinary source checks select workspace library tests; the benchmark
and its timing assertion remain available for explicit native performance runs.
ARM cross compilation does not execute target tests or benchmark code.

See the [patch-retirement record](../../../../docs/research/artcraft-patch-retirement-research.md) for this source update. Earlier completed build receipts apply only to their recorded revisions.
