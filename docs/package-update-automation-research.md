# Package update automation research

Reviewed 2026-09-24; release gate rechecked 2026-09-25. Scope: the source-built packages in this repository and
Nixpkgs revision `44a91898084f46797b5fac650c7e8c9ac38c43d4` pinned by
`flake.lock`. The question is which parts of a release update can be generated
and checked mechanically, and which changes require a compatibility decision.

## Answer

Automate release discovery, immutable source selection, hash and dependency
refresh, structural checks, and builds. Publish the resulting changes as a
reviewable pull request. A successful hash refresh proves which bytes were
fetched, not that a new plugin ABI, permission set, analyzer rule set, or signed
application behaves as intended. In this repository, those semantic changes
should stop or flag an automated proposal. This distinction follows from
[Nixpkgs' update-script contract](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/pkgs/README.md#automatic-package-updates)
and its distinction between package builds and
[functional tests](https://nixos.org/manual/nixpkgs/unstable/#sec-package-tests).

The repository already has [updater discovery](../scripts/update_packages.py),
a [scheduled update pull request](../.github/workflows/update-packages.yml),
and [read-only build selection](../.github/workflows/ci.yml). These cover
packages with `update.py`; the source compositions below lack that entry point.
Package-local updaters for Moonfin, Moonbase, PSScriptAnalyzer, and Subtitle Extract now use the
same preview, validation, and PR path with release-specific gates. The
scheduled dispatcher can preserve successful updates when a failed updater
has made no working-tree changes.

## Findings and sources

### Use standard update entry points without assuming they solve composition

Nixpkgs accepts an executable, a command list, or an attribute set in
`passthru.updateScript`. Its update runner sets `UPDATE_NIX_*` environment
variables, can run scripts in parallel, and warns scripts not to assume a
working directory or create commits. An updater in this repository should keep
its implementation beside `package.nix`, resolve files from `__file__`, and
advertise a command that works from a copied package directory as required by
the [package standard](package-standard.md#updates-and-verification).
[Source: Nixpkgs package contributor guide](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/pkgs/README.md#automatic-package-updates).

`nix-update` can update ordinary versions and source hashes; it supports
`--flake`, `--build`, `--test`, `--format`, `--use-update-script`, custom
dependency hashes, and a `--subpackage` interface for multiple fixed-output
sources exposed in passthru. Its documented subpackage example is a useful
pattern for simple multi-source packages, but a separate updater remains
appropriate when the versions are independently released or must pass manifest
and ABI checks. [Source: nix-update README at `d23a574`](https://github.com/Mic92/nix-update/blob/d23a574edb7560505af9ccb472d0baeec5aae130/README.md).
An unqualified `nix-update` run must not be treated as sufficient for Moonbase's
independent plugin and web releases.

[GitHub's Releases API](https://docs.github.com/en/rest/releases/releases)
offers release metadata and assets, while its
[Git tag API](https://docs.github.com/en/rest/git/tags) distinguishes annotated
tag objects from the commits they name. Resolve the chosen tag to an immutable
commit, reject drafts/prereleases unless explicitly requested, and retain the
tag and commit where both matter. This is an implementation recommendation;
GitHub release ordering alone is not an application compatibility guarantee.
[Nixpkgs fetchers](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/doc/build-helpers/fetchers.chapter.md)
verify fetched content with fixed-output hashes. Refreshing those hashes does
not certify the origin or compatibility of a changed release.

### Refresh each ecosystem's dependency graph with its own tool

For `buildDotnetModule`, Nixpkgs recommends the derivation's `fetch-deps`
passthru to regenerate `deps.json` from the new source and then building the
package. The script may need an explicit destination when its `nugetDeps` path
is not locally writable. Do not carry the old graph forward merely because
the build still evaluates.
[Source: Nixpkgs .NET guide](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/doc/languages-frameworks/dotnet.section.md#generating-and-updating-nuget-dependencies).

Nixpkgs' Flutter builder accepts a parsed `pubspec.lock` as `pubspecLock` and
requires hashes for Git dependencies in `gitHashes`; it recommends a pinned
Flutter SDK rather than the moving `flutter` alias. Dart recommends committing
application lockfiles, and `pub get --enforce-lockfile` fails when the lock
cannot resolve the pubspec or a hosted package's content hash changes.
Therefore copy and parse the upstream release's lockfile, resolve exact Git
revisions, refresh only their hashes, and build with the existing pinned SDK.
Do not run `pub upgrade` during a package version refresh: it makes a second,
independent dependency update.
[Sources: Nixpkgs Dart/Flutter guide](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/doc/languages-frameworks/dart.section.md),
[Dart `pub get` reference](https://dart.dev/tools/pub/cmd/pub-get).

For Intro Skipper, Nixpkgs' `fetchPnpmDeps` and `pnpmConfigHook` use the source
lockfile and a fixed-output store; `sourceRoot` and `pnpmRoot` must refer to the
same subproject. Refresh the pnpm hash from the selected source, keeping its
pinned pnpm major and `fetcherVersion` unless an explicit tooling update is
intended. [Source: Nixpkgs JavaScript guide](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/doc/languages-frameworks/javascript.section.md#javascript-pnpm).

For nd-lyrics, `buildRustPackage`'s `cargoHash` pins the vendored crate
sources; Nixpkgs verifies its relationship to `Cargo.lock`. The new source
hash and Cargo hash can be generated automatically, then checked by the WASI
build and Navidrome's plugin validator. For the Navidrome AudioMuse plugin,
refresh the Nixpkgs Go vendor hash only after the upstream manifest's requested
permissions pass the package's existing allowlist transformation.
[Source: Nixpkgs Rust guide](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/doc/languages-frameworks/rust.section.md#compiling-rust-applications-with-cargo).

### Package-specific acceptance gates

The current recipes and their constraints are recorded in the
[source provenance review](source-provenance-review.md).

| Package | Mechanical refresh | Stop or require targeted review when |
| --- | --- | --- |
| `jellyfin-plugin-moonbase` | Select a plugin release, pin its commit and hash, obtain the web revision/version specified by that release or an explicit compatibility mapping, refresh both source hashes, `deps.json`, Flutter lock JSON and Git hashes; build server, web, and combined output. | Plugin manifest `targetAbi`, assembly inventory, permissions, license/notice files, or web compatibility mapping changes unexpectedly. The two upstream releases cannot be assumed to share a version. |
| `moonfin` | Pin a Core release's Linux commit/hash, convert its committed Dart lock, refresh Git hashes, and verify the selected macOS asset's hash; build Linux and the macOS package on their respective hosts. | Flutter SDK constraint, native plugin requirements, unsigned/unrecognized macOS asset, or source/assets release identity changes. A Linux build does not validate macOS signing or GUI behavior. |
| `psscriptanalyzer` | Pin the GitHub tag and Gallery help archive, refresh both hashes and `deps.json`, build and run the existing import/rule-detection check. | The shipped analyzer rules, severity defaults, API targets, notices, or Gallery help/assembly correspondence changes in a way that affects consumers. Run consumer script checks to expose new diagnostics. |
| `jellyfin-plugin-intro-skipper` | Refresh tag commit/source hash, NuGet graph and pnpm hash; build the embedded dashboard and plugin. | Jellyfin target version, FFmpeg/Chromaprint assumptions, manifest shape, or embedded asset checks change. |
| `jellyfin-plugin-subtitle-extract` | Refresh tag/source hash and NuGet graph; derive metadata from the new upstream `build.yaml`; build. | Manifest target ABI or plugin identity changes; confirm the service still targets the same Jellyfin release. |
| `nd-lyrics` | Refresh source and Cargo hashes; build WASI `.ndp`; validate archive and plugin with Navidrome. | Plugin permissions, Navidrome minimum version, manifest identity, or SDK compatibility changes. |
| `navidrome-plugin-audiomuseai-personal` | Refresh source and Go vendor hashes and build through the Nixpkgs plugin recipe. | `permissions.http.requiredHosts` is neither the expected wildcard nor the local loopback value, or Navidrome/plugin manifest compatibility changes. The current build deliberately fails closed on other permissions. |

The [Moonbase 2.3.0 release](https://github.com/Moonfin-Client/Plugin/releases/tag/2.3.0)
illustrates a real release ordering issue: its tagged
[`Jellyfin/manifest.json`](https://github.com/Moonfin-Client/Plugin/blob/2.3.0/Jellyfin/manifest.json)
does not list 2.3.0, but the later
[master manifest](https://github.com/Moonfin-Client/Plugin/blob/master/Jellyfin/manifest.json)
does. The updater now resolves the latter to a commit, pins its file hash,
checks the plugin identity, release asset, ABI, and web version, and uses that
file to generate `meta.json`. The build never reads a moving master branch.
The Moonfin Web 2.6.0 lock requires Flutter 3.47; the web builder pin was
raised to that line, and both Flutter updaters now stop when a future lock
requires a newer line than their pinned builders.
Flutter's [standard web release build](https://docs.flutter.dev/deployment/web)
compiles Dart to JavaScript; `--wasm` adds a WebAssembly target and still emits
a JavaScript fallback. The Moonbase package matches upstream's WebAssembly
release target. Flutter compiles the JavaScript fallback first, then reuses it
when compiling WebAssembly. This avoids running both large compilers at once,
The concurrent build failed in the WebAssembly optimizer while the serial build
completed; memory pressure is the likely cause, but the failure was not traced
to a specific allocation. The package also retains the separate SQLite
WebAssembly asset required at runtime.

For an update that passes static gates, preview the exact file diff before
writing, write all related pins and locks as one transaction, and leave the
working tree unchanged on failed download or validation. A dry run should
report selected releases, old and new versions, expected files, hash changes,
and compatibility findings without editing files. These are recommendations
for this repository's updater contract, not claims about automatic behavior of
the upstream tools.

### Validation and CI boundary

Run format, updater unit tests, package evaluation with import-from-derivation
disabled, and a build of each changed package on a supported system. Keep
install checks and package-specific smoke checks in the derivations so the
same checks run in local and hosted builds. The repository already enforces
these layers through [its package standard](package-standard.md#updates-and-verification)
and [CI build workflow](../.github/workflows/ci.yml). The update workflow's
separate validation dispatch is intentional: GitHub documents that a push
made with `GITHUB_TOKEN` does not ordinarily trigger `push` or `pull_request`
workflows. [Source: GitHub Actions trigger documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).

Keep the updater's write token out of build jobs and run untrusted source
checks with read-only permissions. GitHub's security guidance calls for least
privilege and warns that `pull_request_target` with checked-out pull request
code is high risk. The existing update workflow's separate PR validation
and [dependency review workflow](../.github/workflows/dependency-review.yml)
are aligned with that separation.
[Sources: GitHub Actions security guide](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target),
[GitHub dependency review](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependency-review).

## Validation and limits

This note was checked against the pinned Nixpkgs revision and the current
package expressions and workflows on 2026-09-24. It is a research and design
record; it does not claim that a newly proposed updater has run, that a GUI
was exercised, or that any new upstream release is compatible. API responses
and release assets can change, so an implementation must test the exact
selected release and fail when expected metadata is missing.

## Implication for this repository

The Moonfin, Moonbase, PSScriptAnalyzer, and Subtitle Extract entry points now use updater
discovery and the PR workflow, with `passthru.updateScript` and package-local
compatibility checks. Other source compositions in the table remain candidates
for the same approach. A failed gate should name the exact missing evidence
while leaving that package unchanged; the dispatcher can still propose
independent successful updates.

## Updater and release-pin review, 2026-10-12

This review uses Nixpkgs `151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4`,
including nix-update 1.16.0. It covers updater entry points and pin storage.
Existing ABI, signature, licensing, payload and dependency compatibility checks
still govern acceptance of a new release.

### Upstream command contract

Nixpkgs accepts an executable, argument list or command attribute set in
`passthru.updateScript`. Its runner supplies `UPDATE_NIX_NAME`,
`UPDATE_NIX_PNAME`, `UPDATE_NIX_OLD_VERSION` and `UPDATE_NIX_ATTR_PATH`.
It does not supply a package directory. Updaters must account for different
working directories and parallel invocation, and leave commits to the runner.
The optional commit feature requires the documented JSON output protocol.
[Source: pinned contributor guide](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/README.md#automatic-package-updates).

The runner rewrites absolute command arguments rooted in the evaluated
checkout to its temporary update worktree. It cannot rewrite a path embedded
in a generated wrapper's body. Each package now exposes its native launcher
and a separate `--source-directory` argument. The launcher executes the
editable package's Python file, preserving sibling imports. An explicit
`--package-dir` or `UPDATE_NIX_PACKAGE_DIR` supports callers outside a checkout.
Otherwise it discovers the package beneath the caller's checkout. Store copies
are never editing targets.
[Source: pinned runner](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/maintainers/scripts/update.py).

Package-local `writeShellApplication` helpers declare the native Python
environment, Nix, certificates and required tools. Application builders do not
inherit these updater dependencies. The repository dispatcher builds the same
helpers against its locked Nixpkgs input. Dependency refreshers use that
declared source, with `NIX_PATH` or a documented selector for direct Python
invocations. No updater reconstructs a personal flake through fixed ancestry.
[Source: native writer implementation](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/build-support/trivial-builders/default.nix).

### Generic helpers and pin files

Use `nix-update-script` for conventional releases when its discovery and
replacement rules fit the package. Custom updaters remain appropriate for
independent component versions, compatibility mappings, signed bundle checks
and structured font inventories. The packages retain their existing release
selection and acceptance checks.
[Source: pinned helper](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/by-name/ni/nix-update/nix-update-script.nix).

nix-update 1.16.0 selects the edited filename from the declaration position of
`src` before metadata fallback. Recipes that import pins from `source.nix` can
therefore need `--override-filename`. Its README warns about replacement in
files containing several versions. The pinned version does not supply
`UPDATE_NIX_FLAKE`; updater scope selection must not depend on that variable.
[Sources: README](https://github.com/Mic92/nix-update/blob/v1.16.0/README.md),
[evaluator](https://github.com/Mic92/nix-update/blob/v1.16.0/nix_update/eval.nix),
[execution implementation](https://github.com/Mic92/nix-update/blob/v1.16.0/nix_update/update.py).

The by-name layout requires `package.nix` and permits accompanying files.
Upstream does not mandate a filename for release pins. This repository uses
`source.nix` for ordinary versions, revisions and hashes, and JSON for payload
inventories and dependency graphs. Preserve upstream lockfiles and separate
platform releases. Converting an inventory into Nix solely for uniform naming
would remove useful structure without meeting an upstream requirement.
[Source: by-name guide](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/by-name/README.md).

Nixpkgs recommends `hash` over older algorithm-specific attributes and accepts
several encodings. SHA-256 SRI is this repository's convention. A flat vendor
download and an unpacked source have different hash meanings. Git fetcher
submodules and post-processing also affect output. Refresh hashes using the
actual fetcher configuration whenever inputs change. A retained known hash can
cause Nix to reuse an old fixed-output store object.
[Source: fetcher guide](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/doc/build-helpers/fetchers.chapter.md).

`nix store prefetch-file --json --hash-type sha256` hashes downloaded bytes;
`--unpack` hashes extracted store contents. Dependency hashes represent the
corresponding builder's output. Generate them from the staged release and its
existing toolchain. For .NET, pass the candidate `deps.json` path explicitly to
`fetch-deps`, since its default output can be inside the store. Application
updates retain upstream locks rather than upgrading dependency ranges.
[Sources: Nix prefetch manual](https://nix.dev/manual/nix/2.28/command-ref/new-cli/nix3-store-prefetch-file),
[.NET guide](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/doc/languages-frameworks/dotnet.section.md),
[Rust guide](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/doc/languages-frameworks/rust.section.md).

### Repository implementation and verification

Related pins and generated dependencies publish through package-local
transaction helpers. They stage unique sibling files, preserve modes and
restore originals after ordinary write failures or Python interruptions.
Restoration failures retain recovery files and report their paths. This
provides rollback, not filesystem-wide atomicity or recovery after power loss
or `SIGKILL`. The helper checks for changes during publication; callers should
avoid editing the same pins during a long update.

Moonfin, Moonbase, Subtitle Extract, PSScriptAnalyzer and Windows font previews
include the candidate auxiliary files before publication. A full composition
preview can download sources and generate dependencies. Wardrowbe updates its
own folder by default; the local dispatcher requests paired updates explicitly
so upstream can run its two package updaters independently. The dispatcher
compares file contents, modes and symlinks as well as Git status before allowing
partial success after another updater fails.

The `source-pins` check rejects malformed or placeholder SHA-256 SRI hashes and
common moving branch and release names in `source.nix`. Existing package validators retain
responsibility for JSON inventories and dependency structures. Native updater
checks exercise every launcher with an empty caller PATH, standalone copies,
local imports and separate editable-path arguments. Unit tests exercise
rollback, permissions, Unicode path quoting and selected dependency scope.
These fixture checks do not establish that a future upstream release will
build. No release versions or source hashes were upgraded in this review.
