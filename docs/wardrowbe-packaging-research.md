# Wardrowbe dependency packaging research

Reviewed: 2026-09-26. Scope: Wardrowbe 1.10.1 and the official Nixpkgs
documentation and package expressions retrieved on that date. This supplements
[the package design research](package-design-research.md) with the dependency
decisions specific to Wardrowbe.

## Answer

Prefer dependencies from the caller's Nixpkgs package set. Keep the application's
release hash and npm dependency hash for reproducibility. Add a dependency
override only after demonstrating a compatibility or build failure, and document
the condition that permits removing it. This recommendation follows the existing
[package standard](package-standard.md) and the evidence below.

## Findings and sources

### Python dependencies

Nixpkgs creates a separate library package set for each Python interpreter.
Using one interpreter's `withPackages` keeps dependencies in that set. Its
override mechanism can replace a package when a demonstrated compatibility issue
requires it. `pythonRelaxDeps` changes version constraints in wheel metadata;
it does not repair an incompatible API. The manual prefers relaxing constraints
to removing dependencies. Unit tests provide stronger evidence than an import
check, although `pythonImportsCheck` remains useful without a runnable suite.
[Nixpkgs Python reference](https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/python.section.md)

Wardrowbe 1.10.1 declares `redis>=5.0.1` and `arq>=0.25.0`, without upper
bounds. These requirements alone do not justify maintaining separate pinned
recipes. ARQ 0.28 itself requires `redis[hiredis]>=4.2.0,<6`. The locked nixpkgs
Python set has no ARQ and supplies Redis 8.0.1, so the local fallback currently
needs the older Redis client. Reuse both upstream once ARQ is available.
[ARQ 0.28 dependency bounds](https://github.com/python-arq/arq/blob/v0.28.0/pyproject.toml)
[Wardrowbe 1.10.1 requirements](https://github.com/Anyesh/wardrowbe/blob/wardrowbe-v1.10.1/backend/requirements.txt)

Nixpkgs supplies a Python ONNX Runtime package built from the native
`onnxruntime.dist` output. It handles native library references and optional CUDA
dependencies. Its expression documents a sandbox import failure on
`aarch64-linux` because CPU information is unavailable. Reusing this package
therefore avoids maintaining a separate manylinux wheel recipe, but an ARM
build must account for that documented test limitation.
[Nixpkgs Python ONNX Runtime expression](https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/python-modules/onnxruntime/default.nix)

### Font assets and frontend reproducibility

Nixpkgs' `inter` package fetches Inter 4.1 with the same release archive and hash
as Wardrowbe's original local font fetch. It installs font assets and records the
OFL license. Taking the required variable TTF from that package removes duplicate
source maintenance. Packaging review should preserve the font's license notice
when bundling it into the frontend.
[Nixpkgs Inter expression](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/in/inter/package.nix)

Nixpkgs fetchers use fixed-output derivations and verified content hashes. Keep
asset fetching in these declared inputs so the ordinary build can work without
network access. This applies to replacing Next.js' build-time Google Fonts
download with a local asset.
[Nixpkgs fetcher reference](https://github.com/NixOS/nixpkgs/blob/master/doc/build-helpers/fetchers.chapter.md)

`buildNpmPackage` uses the npm lockfile and `npmDepsHash` for its dependency
cache. The npm hash remains necessary after replacing unrelated Python or font
dependencies. A package recipe should use this builder's dependency handling
rather than run an unpinned installation during its build.
[Nixpkgs JavaScript reference](https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/javascript.section.md)

### Binary caches and tests

Nix obtains existing store objects from configured substituters when available.
The default substituter is `cache.nixos.org`; trust and signatures still apply.
An upstream attribute's existence does not establish cache availability for a
particular Nixpkgs revision, platform, Python version, or override. Check the
actual build plan before promising that a dependency will avoid compilation.
[Nix substituter configuration](https://nix.dev/manual/nix/stable/command-ref/conf-file.html#conf-substituters)

Nixpkgs supports consumer tests through `passthru.tests`. They must be selected
by the check workflow to provide evidence; defining them alone does not run
them in a normal package build. Wardrowbe verification should cover its installed
entry points and relevant worker behavior, in addition to dependency imports.
[Nixpkgs passthru test reference](https://github.com/NixOS/nixpkgs/blob/master/doc/stdenv/passthru.chapter.md)

## Validation and limits

This investigation read the existing backend and frontend recipes and the
primary sources above. It ran no package builds, runtime checks, security audit,
or cache availability checks. Nixpkgs `master` links describe upstream guidance
and may change; the repository's locked Nixpkgs input determines the versions
and expressions actually used. Build and service evidence belongs in the
implementation's validation report.

## Automated release updates

Reviewed: 2026-09-26. Extend the repository's existing
[update automation](package-update-automation-research.md) with one Wardrowbe
update operation that refreshes both package directories. Backend and frontend
come from the same upstream release archive; selecting them independently can
introduce an API mismatch. Keep their release version, immutable commit, and
source hash together, while refreshing the frontend dependency hash from that
commit's lockfile. This is a packaging recommendation, not an upstream
compatibility guarantee.

Upstream's root release configuration identifies the component as `wardrowbe`.
The Releases API returned stable `wardrowbe-vX.Y.Z` releases through 1.10.1;
the Tags API also contained legacy `v1.2.0`. Filter release tags by the component
and numeric version, reject drafts and prereleases, and resolve the selected tag
to its commit. Do not infer the application release from
`frontend/package.json`: it still declares version 1.2.0 in the 1.10.1 release.
[Release configuration](https://github.com/Anyesh/wardrowbe/blob/wardrowbe-v1.10.1/release-please-config.json),
[release history](https://github.com/Anyesh/wardrowbe/releases),
[frontend manifest](https://github.com/Anyesh/wardrowbe/blob/wardrowbe-v1.10.1/frontend/package.json),
[GitHub tags API](https://docs.github.com/en/rest/repos/repos#list-repository-tags).

Nixpkgs documents `prefetch-npm-deps package-lock.json` for calculating
`npmDepsHash`. Use the tool from the locked Nixpkgs input with the selected
release's frontend lockfile; do not run `npm update` to produce a different
dependency graph. The pinned implementation accepts an optional second
positional output directory, which suppresses printing the hash. It does not
offer a JSON-output or hash-only flag. `NIX_BUILD_CORES` bounds its download
parallelism. Keep its output format and fetcher settings aligned with the
builder instead of reconstructing the npm cache in a custom implementation.
[JavaScript packaging reference](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/doc/languages-frameworks/javascript.section.md),
[pinned prefetch implementation](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/pkgs/build-support/node/prefetch-npm-deps/src/main.rs).

Expose the updater through `passthru.updateScript`, use package-local paths,
and avoid committing changes from the updater. Nixpkgs' runner supplies package
metadata through `UPDATE_NIX_*` variables and does not guarantee the working
directory. Retain the existing scheduled pull-request workflow and its separate
read-only validation rather than add another release scheduler.
[Nixpkgs update-script contract](https://github.com/NixOS/nixpkgs/blob/44a91898084f46797b5fac650c7e8c9ac38c43d4/pkgs/README.md#automatic-package-updates).

Recommended acceptance gates are agreement between both installed pins,
presence and parseability of upstream frontend manifests and lockfile,
successful application of both local compatibility patches, backend dependency
availability, and unchanged expected license files and entry points. Refresh
all pins only after downloading and validating the candidate successfully.
Fail with an actionable error when an upstream layout, lock format, dependency,
or patch changes. Build both packages and run their consumer tests before
accepting the proposed update. A successful hash refresh establishes fetched
content; it does not validate database migration reversibility or OIDC login.

### Fallback Python dependency updates

The ARQ/Redis fallback can refresh independently of Wardrowbe releases. Select
a stable, non-yanked ARQ source distribution, parse its `requires_dist` Redis
requirement, and select a stable, non-yanked Redis source distribution satisfying
that constraint. Check `requires_python` against the selected interpreter and
stop on an unexpected dependency inventory. Use PyPA's `Requirement` and
`SpecifierSet` parsers so extras, environment markers, and version comparisons
are handled explicitly rather than by string matching.
[Requirement parser](https://packaging.pypa.io/en/stable/requirements.html),
[version specifier parser](https://packaging.pypa.io/en/stable/specifiers.html).

PyPI's release JSON exposes dependency metadata, Python constraints, distribution
URLs, SHA256 digests, and per-file yanked flags. Its metadata comes from upload
time and may differ from the distribution itself; a metadata gate therefore
does not replace building and testing the selected sources. Convert the chosen
sdist's SHA256 digest to Nix SRI and let the fixed-output fetch verify its bytes.
Check the source distribution's yanked flag, not only the release summary.
For version discovery, prefer the Index API: the project JSON `releases` field
is deprecated. Use the release-specific JSON endpoint for candidate metadata.
[PyPI JSON API](https://docs.pypi.org/api/json/),
[PyPI Index API](https://docs.pypi.org/api/index-api/).

This follow-up inspected official documentation, the pinned prefetch source,
and live upstream release/tag metadata. It performed no builds, migrations,
deployment, or browser checks. Implementation checks must report their own
results and platform coverage.
