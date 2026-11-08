# VectorCraft

Source build of [VectorCraft 0.12.0](https://github.com/storytold/vectorcraft/releases/tag/v0.12.0) at `8bc65329286dc1b84aa392997bb205613c3e96cb`.
Installs `vectorcraft` and `vectorcraft-cli`, retaining the default automation/plugin capabilities.
The pinned craft-fonts collection is embedded with required-input checking for multilingual text.

Linux includes X11/Wayland and Vulkan/OpenGL loader paths, desktop entries, icons and available MIME definitions. macOS includes a native app bundle with upstream document declarations and an ad-hoc signature. The CLI remains independently invocable. Browser/WASM targets and developer xtask are not desktop deliverables.

Linux printing uses packaged CUPS clients and the host’s configured printing service.

The build runs native workspace library tests and installed CLI/desktop checks. Separate package checks exercise document exports and GUI startup. Tests needing external corpora, optional models, services or physical devices need separate upstream integration runs. See [the packaging research and validation record](../../../../docs/artcraft-packaging-research.md) for completed checks and platform limits.

The public flake exports x86_64-linux, aarch64-linux and aarch64-darwin. For Intel macOS, call this independent recipe with `pkgs.callPackage ./package.nix { }` from a Nixpkgs 26.05 instance providing Rust 1.95 or newer. Nixpkgs 26.11 dropped Intel Darwin support, so the current public flake and its overlay do not expose that system.

Updates are manual: inspect an upstream release/commit and its manifests, asset terms and packaging templates; update `source.nix` and its release metadata, review and refresh the checked-in Cargo locks and font pin, recompute immutable source and Git dependency hashes, then rebuild with strict sandboxing. These projects are early alpha with rapidly changing interfaces, so unattended updates are not enabled.

Non-NixOS graphics can require [nixGL](https://github.com/nix-community/nixGL) using the same Nixpkgs pin as this package.

Upstream 0.12.0 registers every supplied Craft font family while preserving
Japanese, Arabic and Thai fallback priority. The former local registration patch
has been removed; upstream regressions cover family/style registration, empty
font input and mixed-script ordering. The release's shared PDF reader/writer and
its Git dependencies are pinned with the upstream Cargo lockfile.
Dependency notices retain their complete referenced `licenses/` trees, including
the PDF writer's MIT/Apache and ICC-profile terms. A packaging regression checks
original paths and bytes as well as the root licenses and source metadata.

See the [patch-retirement record](../../../../docs/research/artcraft-patch-retirement-research.md) for this source update. Earlier completed build receipts apply only to their recorded revisions.
