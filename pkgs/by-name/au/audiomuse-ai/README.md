# AudioMuse-AI

This recipe installs AudioMuse-AI from the tagged source pinned in source.nix. It uses the
pinned Nixpkgs Python 3.13 package set and fetches each upstream ONNX/model
release artifact by SHA-256. It does not use the upstream container or
PyInstaller bundle. Python 3.13 is the closest cache-backed Nixpkgs interpreter
newer than upstream's Ubuntu 24.04 Python 3.12 baseline. Dependency import
checks and selected upstream suites provide partial compatibility evidence;
the former package-owned application and NixOS service checks are retired.

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
Nixpkgs with their ordinary upstream checking configuration, avoiding a
private duplicate of the entire Python ecosystem. Safetensors, Narwhals and the
scikit-learn dependency chain use their unmodified Nixpkgs recipes.

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
generated-file string. The generated table and wheel metadata retain the
reviewed runtime requirement. The former application install check and
`audiomuse-ai-python` project check are retired; dependency import checks remain.

The Nixpkgs Tokenizers 0.23.3 update requires extending that reviewed upper
bound from 0.23.2. Its [release](https://github.com/huggingface/tokenizers/releases/tag/v0.23.3)
fixes truncation/overflow handling and Python metadata; the
[source comparison](https://github.com/huggingface/tokenizers/compare/88a4498ad4ea1a9487b0a9b0ff881383fd5a06a3...301277072263fb3830eb66eec7e47adadf76f1dc)
records the changes. Historical project-owned tokenizer reload, token-ID,
batch-padding and overflow checks are retired. The Tokenizers recipe now keeps
upstream's offline suite and pinned local test data. It excludes the tutorial
file whose already-disabled network training cases import `datasets`, avoiding
a second incompatible Hub version in the check environment. Future versions
remain review-gated.

The updater deliberately does not invent versions for packages supplied by
Nixpkgs. Changes to those upstream pins are review-gated and must be handled by
the Nixpkgs input update or an explicit compatibility change. Run
`nix build .#audiomuse-ai.pythonEnvironment` to build the
Python dependency closure without downloading the model artifacts. Use
`--refresh` when intentionally revalidating all application and API-sensitive
Python source hashes.

After an accepted update, build audiomuse-ai and perform a service-level smoke
test on the target host. The large model closure remains separate from the
Python dependency environment.

The Mistral SDK recipe removes Invoke from its runtime dependencies. Upstream
uses that task runner only in the repository's development tasks, outside the
SDK wheel. Keeping it as a runtime dependency caused issue #157 when the
consumer's Nixpkgs supplied Invoke 3 while the SDK metadata required Invoke 2.
The recipe uses `pythonRemoveDeps` rather than a version pin or a relaxed
constraint; all remaining wheel runtime requirements are still checked.
The SDK retains its import check. The former project-owned in-memory completion
and blocked-Invoke check is retired; authenticated client operation needs
separate validation after updates.

## Retained upstream tests

The pinned Hub recipe runs upstream validators, authentication-header, path,
chunking and datetime tests with offline mode enabled. The pinned Transformers
recipe runs upstream model-output, deprecation, version, argument-parser and
logging tests against the selected Hub, Safetensors and Tokenizers. Optional
frameworks and accelerators stay outside these utility check environments;
model downloads and authenticated services require separate native acceptance.
The Google GenAI and Mistral recipes retain dependency import checks. The
selections are defined in [`package.nix`](package.nix),
[`huggingface-hub.nix`](huggingface-hub.nix) and
[`transformers.nix`](transformers.nix).

Focused x86_64-linux validation on 2026-11-16 passed 182 Tokenizers tests
(3 skipped, 18 deselected), 42 Hub tests, and 41 Transformers tests
(5 skipped for optional Torch). These upstream cases replace blanket dependency
test suppression; they do not restore the retired project-owned application
checks or establish inference quality, search relevance or service readiness.
