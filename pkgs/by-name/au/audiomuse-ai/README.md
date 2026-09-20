# AudioMuse-AI

This recipe installs AudioMuse-AI 3.6.0 from its tagged source. It uses the
pinned Nixpkgs Python 3.13 package set and fetches each upstream ONNX/model
release artifact by SHA-256. It does not use the upstream container or
PyInstaller bundle. Python 3.13 is the closest cache-backed Nixpkgs interpreter
newer than upstream's Ubuntu 24.04 Python 3.12 baseline; the package import
check and NixOS service test guard that compatibility choice.

The application and Python dependency closure use source-oriented Nixpkgs
recipes. Nix may substitute a trusted binary-cache result when its derivation
hash matches; this is the normal cached result of the same source recipe, not
an upstream binary release. The ONNX and tokenizer data are upstream model
artifacts rather than buildable application sources, so they remain
fixed-output downloads with declared hashes and binary-model provenance. The
native service currently uses CPU ONNX Runtime: the pinned Nixpkgs revision
does not provide the matching CUDA 13 ONNX Runtime and cuML stack, and upstream
still describes that path as experimental.

The package exposes one command for each upstream process role. A service
manager should run the web, high-priority worker, default worker, maintenance,
and control roles together. It must supply PostgreSQL connection credentials and
writable application, plugin, temporary-audio, cache, and log directories.

Model files account for most of the closure. They are kept in a separate
derivation so source-only updates do not rebuild or duplicate them. The recipe
removes model weights that upstream's own native-build assembly identifies as
unused.

AudioMuse-AI's API-sensitive client libraries are pinned to compatible tagged
sources. The numerical and media stack comes from this repository's pinned
Nixpkgs after compile and import checks, avoiding a private duplicate of the
entire Python ecosystem.

## Updates

Run python3 pkgs/by-name/au/audiomuse-ai/update.py --dry-run from the package
repository root to preview the latest stable application release. The updater
resolves the release tag to a full commit, verifies the source hash with Nix,
checks the upstream Python requirement and model-release contract, and checks
the source paths and patch anchors used by the Nix recipe before writing
source.nix atomically. When an application release changes one of the
API-sensitive Python requirements, the updater also resolves that dependency's
version tag to an immutable commit and refreshes its source hash in the same
manifest. A change to the model release, the Nixpkgs-backed requirements, or a
required source contract stops the updater without modifying any pins.

The machine-owned source.nix manifest keeps application source, model
artifacts, Nixpkgs compatibility pins, and API-sensitive Python sources in
separate blocks. The Transformers recipe patches its canonical setup.py
dependency declaration and regenerates the derived runtime table, so a
Nixpkgs tokenizers update cannot invalidate a patch against an unrelated
generated-file string. The application install check and the lightweight
`audiomuse-ai-python` CI check import the resulting stack and verify the
installed tokenizers version against the reviewed runtime requirement.

The updater deliberately does not invent versions for packages supplied by
Nixpkgs. Changes to those upstream pins are review-gated and must be handled by
the Nixpkgs input update or an explicit compatibility change. Run
`nix build .#checks.x86_64-linux.audiomuse-ai-python` to build and check the
Python dependency closure without downloading the model artifacts. Use
`--refresh` when intentionally revalidating all application and API-sensitive
Python source hashes.

After an accepted update, build audiomuse-ai and perform a service-level smoke
test on the target host. The large model closure remains separate from the
automated Python dependency check.
