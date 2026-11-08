# PdfCraft

Source build of [PdfCraft 0.8.0](https://github.com/storytold/pdfcraft/releases/tag/v0.8.0) at `9931329b9fae0b05373b4dc3ac7c58541f0891a4`.
Installs `pdfcraft` and `pdfcraft-cli`, retaining the default automation/plugin capabilities.
The pinned CC-BY-SA OCR detection and recognition models are bundled, with their notices, and used by the native OCR test.
A policy-filtered, immutable font input is embedded with required-input checking for multilingual text.
Restricted ArtCraft logo artwork is replaced with plain text; app icons, file types and functionality remain from upstream.

Linux includes X11/Wayland and Vulkan/OpenGL loader paths, desktop entries, icons and available MIME definitions. macOS includes a native app bundle with upstream document declarations and an ad-hoc signature. The CLI remains independently invocable. Browser/WASM targets and developer xtask are not desktop deliverables.

Linux printing uses packaged CUPS clients and the host’s configured printing service.

The build runs native workspace library tests and installed CLI/desktop checks. Separate package checks exercise document exports and GUI startup. Tests needing external corpora, optional models, services or physical devices need separate upstream integration runs. See [the packaging research and validation record](../../../../docs/artcraft-packaging-research.md) for completed checks and platform limits.

The public flake exports x86_64-linux, aarch64-linux and aarch64-darwin. For Intel macOS, call this independent recipe with `pkgs.callPackage ./package.nix { }` from a Nixpkgs 26.05 instance providing Rust 1.95 or newer. Nixpkgs 26.11 dropped Intel Darwin support, so the current public flake and its overlay do not expose that system.

Updates are manual: inspect an upstream release/commit and its manifests, asset terms and packaging templates; update `source.nix` and its release metadata, review and refresh the checked-in Cargo locks and font pin, recompute immutable source and Git dependency hashes, then rebuild with strict sandboxing. These projects are early alpha with rapidly changing interfaces, so unattended updates are not enabled.

The x86 build patches RTen 0.26.0 to emit the same AVX-512 VNNI instruction with inline assembly. The pinned Rust 1.98.1 compiler rejects the original standard-library intrinsic signature. Runtime CPU detection and OCR remain enabled. Review this workaround when updating RTen or the compiler.

Non-NixOS graphics can require [nixGL](https://github.com/nix-community/nixGL) using the same Nixpkgs pin as this package.

macOS bundles contain the OCR model files directly for Apple signature
verification; the standalone CLI uses its immutable executable-relative model link.

The OCR searchability fixture renders and imports its scan at 300 DPI, preserving
small text strokes and the original physical page size. Its content and every
recognition, placement, undo and repeat-pass assertion remain unchanged.

The build input selects five permitted Japanese/Arabic faces, the original Apache-licensed Droid Sans Fallback with its full NOTICE, and the already attributed Noto Sans Thai face. It excludes the prohibited Source Han-derived Noto CJK input. Source tests cover Thai registration and the permitted Han face's precedence for both Chinese interface variants; font-data checks cover the pinned Chinese catalogs.

## Native Wayland image clipboard

Linux enables arboard's native image backend on compositors advertising
ext-data-control or wlr-data-control with a seat. Other compositors retain the
existing X11 fallback when available. Darwin keeps its native backend.

`passthru.tests.waylandClipboard` compiles a separate source regression and runs
an isolated headless Sway test with DISPLAY unset. It verifies actual Create
from Clipboard and a distinct PNG export through arboard. The original-pin test passed on
native x86_64 Linux; the refreshed release needs a fresh run. It does not establish focused text paste, GUI image-region
selection, ARM clipboard runtime or physical GPU behavior. Test executables and
compositor tools are separate from the ordinary application output.

The common Cargo lock correction retains the three existing log dependencies
required by the enabled Hayro logging feature. Linux layers only the six native
clipboard dependencies onto that corrected input. The common and Linux Cargo locks are checked in with explicit hashes for
Git dependencies; offline source builds and tests reject further lockfile changes.

See the [patch-retirement record](../../../../docs/research/artcraft-patch-retirement-research.md) for this source update. Earlier completed build receipts apply only to their recorded revisions.
