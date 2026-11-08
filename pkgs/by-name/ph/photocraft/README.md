# PhotoCraft

Source build of [PhotoCraft 0.9.0](https://github.com/storytold/photocraft/releases/tag/v0.9.0) at `c699e3cda69f4852b43c0b191ab0091aaeff9d6a`.
Installs `photocraft` and `photocraft-cli`, retaining the default automation/plugin capabilities.
HEIF decoding is enabled, matching upstream official builds.
The pinned craft-fonts collection is embedded with required-input checking for multilingual text.

Linux includes X11/Wayland and Vulkan/OpenGL loader paths, desktop entries, icons and available MIME definitions. macOS includes a native app bundle with upstream document declarations and an ad-hoc signature. The CLI remains independently invocable. Browser/WASM targets and developer xtask are not desktop deliverables.

Linux printing uses packaged CUPS clients and the host’s configured printing service.

The build runs native workspace library tests and installed CLI/desktop checks. Separate package checks exercise document exports and GUI startup. Tests needing external corpora, optional models, services or physical devices need separate upstream integration runs. See [the packaging research and validation record](../../../../docs/artcraft-packaging-research.md) for completed checks and platform limits.

The public flake exports x86_64-linux, aarch64-linux and aarch64-darwin. For Intel macOS, call this independent recipe with `pkgs.callPackage ./package.nix { }` from a Nixpkgs 26.05 instance providing Rust 1.95 or newer. Nixpkgs 26.11 dropped Intel Darwin support, so the current public flake and its overlay do not expose that system.

Updates are manual: inspect an upstream release/commit and its manifests, asset terms and packaging templates; update `source.nix` and its release metadata, review and refresh the checked-in Cargo locks and font pin, recompute immutable source and Git dependency hashes, then rebuild with strict sandboxing. These projects are early alpha with rapidly changing interfaces, so unattended updates are not enabled.

Non-NixOS graphics can require [nixGL](https://github.com/nix-community/nixGL) using the same Nixpkgs pin as this package.

A local patch registers every embedded Craft font, including Chinese and Arabic.
Library tests retain the upstream all-family regression and select a Japanese
locale for the separate Japanese fallback assertion. Runtime locale selection
continues to follow the application settings.

The shortcut-capture unit test retains every keyboard/UI assertion and omits
an unchecked GPU render call; installed GUI checks exercise rendering separately.

On Linux, the benchmark helper uses memory-stats' supported `always_use_statm`
feature, following [upstream #5399](https://github.com/storytold/photocraft/pull/5399).
This avoids the expensive smaps walk and restores positive RSS measurements on
the configured ARM emulator, where smaps synthesizes zero RSS. The original four
testkit tests pass on native and emulated Linux with this feature. Under QEMU,
statm reflects emulator-process accounting, not an isolated guest-only total.
This replaces the ARM-only zero-reading suppression; Darwin remains unchanged.
These focused results do not establish a full application build or sandbox pass.

On native macOS, `hostTests.native` provides the offscreen Metal arrow rendering regression. The source build compiles the original test and excludes only its execution inside the sandbox. Build the separate artifact with `nix build .#photocraft.hostTests.native --option sandbox true --out-link result-native-tests`, then run `./result-native-tests/bin/photocraft-host-tests` on the host. This retains the hardware/service assertions while keeping ordinary source builds sandboxed.

See the [patch-retirement record](../../../../docs/research/artcraft-patch-retirement-research.md) for this source update. Earlier completed build receipts apply only to their recorded revisions.
