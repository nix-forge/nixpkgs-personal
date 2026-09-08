# NUR assessment

Reviewed 2026-09-07. This is a proposal, not a registration or a claim that NUR compatibility has been implemented. Primary-source inspection used NUR commit `1939820a52d6c797f0d64df036eaef18732193a7` and template commit `b885a769f27b0d6dfa815c4497c3694a7412904f`.

My recommendation is to add NUR as an optional distribution route after addressing the compatibility and metadata details below. Keep the direct flake as the primary development and consumption interface. This collection's personal variants, older fonts, and platform-specific applications are a reasonable fit for a user-maintained collection. NUR membership does not require turning them into dependencies of one another.

NUR registers repositories under `nur.repos.<name>`, while maintainers retain responsibility for their contents. It gives the collection a place in the [NUR package search](https://nur.nix-community.org/). NUR does not provide the recurring security review that users might infer from a community name. Its documentation explicitly says repositories are not regularly checked for malicious content. [NUR introduction and usage](https://github.com/nix-community/NUR/blob/1939820a52d6c797f0d64df036eaef18732193a7/README.md)

## Required for submission

- Register a publicly fetchable Git repository in NUR's `repos.json`, format that manifest, and submit the manifest change through a pull request. Do not submit NUR's generated lock file. An alternate entrypoint is supported through `"file": "pkgs/default.nix"`; a root-level `default.nix` is therefore optional. The documented compatibility target is Nixpkgs unstable. [NUR registration instructions](https://github.com/nix-community/NUR/blob/1939820a52d6c797f0d64df036eaef18732193a7/README.md#how-to-add-your-own-repository)
- The entrypoint must accept dependencies through its `pkgs` argument. It must not replace caller-supplied Nixpkgs with the repository's locked input. A default `pkgs` argument is allowed for development convenience. The existing `pkgs/default.nix` already uses the right dependency-injection shape. [NUR template entrypoint](https://github.com/nix-community/nur-packages-template/blob/b885a769f27b0d6dfa815c4497c3694a7412904f/default.nix)
- The current submission checklist requires declaring that copyrightable repository content is MIT licensed, with exceptions stated for built derivations and patches. It separately requires accurate `meta.license` and `meta.sourceProvenance` for unfree packages and packages not built from source. This does **not** mean the packaged applications themselves must be MIT or free software. [NUR submission checklist](https://github.com/nix-community/NUR/blob/1939820a52d6c797f0d64df036eaef18732193a7/.github/PULL_REQUEST_TEMPLATE.md)

The local license scan found the root MIT license, MIT licenses for the three bundled native utilities, and the retained MIT license for the vendored Noctalia expression. No committed font or image binaries were found. This supports the submission declaration; it is not a substitute for verifying ownership of every contributed file. Downloaded upstream programs and artwork retain their own licenses.

The concrete metadata gap is source provenance: the eight standalone Apple developer font packages, `apple-fonts`, and `apple-color-emoji` omit it. Review the prebuilt historical emoji fonts too. Use provenance that reflects the actual inputs; extracting or modifying a compiled font does not make its original source available. Most vendor application wrappers already declare binary native code. Nixpkgs defines provenance independently of licensing. [Nixpkgs metadata reference](https://github.com/NixOS/nixpkgs/blob/master/doc/stdenv/meta.chapter.md#sourceprovenance-var-meta-sourceprovenance)

## Compatibility and CI

NUR's evaluator invokes `nix-env -qa '*' --meta --xml --drv-path` with restricted evaluation, permits import from derivation, sets `NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1`, and imposes a three-minute timeout. It does not set `NIXPKGS_ALLOW_UNFREE`. Passing our existing flake checks does not establish that this different traversal succeeds. In particular, asking for all derivation paths on a Linux host can force platform-specific build attributes that metadata-only discovery leaves lazy. [NUR evaluator](https://github.com/nix-community/NUR/blob/1939820a52d6c797f0d64df036eaef18732193a7/ci/nur/eval.py)

Add an explicit NUR evaluation job before registration. Run against current unstable as well as our locked package input. Keep the existing native Linux and macOS builds and independence checks. Stable-channel testing is optional unless we choose to promise it: the template currently tests `nixpkgs-unstable`, `nixos-unstable`, and `nixos-26.05`, but that template matrix is not itself an admission requirement. [Template workflow](https://github.com/nix-community/nur-packages-template/blob/b885a769f27b0d6dfa815c4497c3694a7412904f/.github/workflows/build.yml)

The local probe using NUR's actual `evalRepo.nix`, its evaluator flags and environment, and this repository's pinned Nixpkgs passed against the existing `pkgs/default.nix`. The same probe passed against current `nixos-unstable`, revision `dc5d91f840324650bac8c379428c7037a416959a`. Both returned 13 entries under the evaluator's default package policy on this Linux host. There is therefore no demonstrated need for an adapter: registering `"file": "pkgs/default.nix"` is sufficient for this tested entrypoint. A root `default.nix` forwarding to it would be an optional convenience.

A stronger diagnostic used current unstable with caller-provided `allowUnfree = true`, selected packages with `lib.meta.availableOn`, and forced all supported derivation paths with import from derivation disabled. All 86 evaluations passed: 27 on `x86_64-linux`, 25 on `aarch64-linux`, and 34 on `aarch64-darwin`. This demonstrates evaluation compatibility at that revision. No fresh package builds were performed for this assessment, and other consumer pins remain untested.

Search visibility is narrower than membership: NUR's current index runs one host's package query, rather than a matrix of every package's platforms. Do not promise that all 39 packages, including unfree and macOS-only ones, will appear in its search results. Keep the README's full platform inventory and direct flake instructions. [NUR indexer](https://github.com/nix-community/NUR/blob/1939820a52d6c797f0d64df036eaef18732193a7/ci/nur/index.py)

Do not silently enable unfree packages in the NUR entrypoint. Keep the consumer's Nixpkgs policy intact and document how users opt in for specific packages. Nixpkgs supports `allowUnfreePredicate` for selective consent. NUR membership does not expand upstream redistribution rights. [Nixpkgs configuration](https://github.com/NixOS/nixpkgs/blob/master/doc/using/configuration.chapter.md#installing-unfree-packages)

Two current NUR implementation details weaken the usual assumptions about its infrastructure:

- The README says updates are checked daily; the inspected workflow schedules updates hourly, at minute 40, and also responds to pushes and manual runs. This is a schedule, not an update-latency guarantee. [NUR update workflow](https://github.com/nix-community/NUR/blob/1939820a52d6c797f0d64df036eaef18732193a7/.github/workflows/update.yml)
- The README describes evaluation before propagation, but the current update function defaults `do_evaluate` to false and its ordinary CLI invocation does not enable it. We should not rely on a guaranteed evaluation gate for each repository update. Our own CI must remain authoritative. [Update implementation](https://github.com/nix-community/NUR/blob/1939820a52d6c797f0d64df036eaef18732193a7/ci/nur/update.py), [CLI dispatch](https://github.com/nix-community/NUR/blob/1939820a52d6c797f0d64df036eaef18732193a7/ci/nur/__init__.py), [Update script](https://github.com/nix-community/NUR/blob/1939820a52d6c797f0d64df036eaef18732193a7/ci/update-nur.sh)

The update notification hook is optional. Add it only after our checks and builds succeed on the published branch. The template demonstrates the hook and a separately configured Cachix cache. NUR registration alone does not provision that cache. Its template deliberately excludes unfree and broken packages from its default build set and excludes `preferLocalBuild` packages from cache outputs. [Template cache selection](https://github.com/nix-community/nur-packages-template/blob/b885a769f27b0d6dfa815c4497c3694a7412904f/ci.nix)

## Tradeoffs and recommended scope

| Choice | Practical benefit | Cost or limitation |
| --- | --- | --- |
| Keep the direct flake | Exact repository revision remains easy to pin; present users keep their interface | People must first discover this repository |
| Add NUR alongside it | Search exposure and a familiar namespace for people already using NUR | Another integration contract, update propagation, and support surface |
| Submit selected packages to Nixpkgs | Broadly useful packages can share upstream maintenance and review | Each package must meet upstream contribution standards; personal variants may remain here |

These are design judgments based on the interfaces above. NUR keeps the source repository independent, so retaining both entrypoints avoids making our users depend on NUR's update cadence. Upstreaming is a separate, package-by-package decision; Nixpkgs has its own review and contribution process. [Nixpkgs contribution guide](https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md)

Before registration, I would add the NUR evaluation job against current unstable, complete the provenance audit, and document a stable public attribute namespace and support policy. Add maintainer/contact information and explain clearly which packages differ from their Nixpkgs counterparts. These are recommendations; NUR does not require a language rewrite, a template directory migration, a separate repository per package, or a dependency on other NUR repositories.

NUR is worthwhile if the intent is to share and maintain this collection for other users. Its benefit is smaller if the repository will remain solely a private configuration dependency. The existing independent package layout and separate flake already provide most of the technical reuse; NUR mainly adds discovery and a common integration point.
