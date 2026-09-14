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
entire Python ecosystem. Recheck upstream's requirements and run the service
test on every update.
