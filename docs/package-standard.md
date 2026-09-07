# Package standard

This repository uses the official guidance linked in [the research](package-design-research.md).
The additional independence requirement applies to all 39 public outputs.

## Directory and dependency contract

Each public attribute has `pkgs/by-name/<first-two-letters>/<name>/package.nix`.
The expression is a function returning a derivation, with dependencies supplied
by upstream Nixpkgs. Keep its source pins, patches, helper modules, tests and
updater in that directory. Do not import sibling packages, repository tooling,
personal configuration modules, flake inputs, or a private Nixpkgs package set.

`pkgs/default.nix` registers platform support and supplies the upstream scope.
It is the only package registry. A public output must not be an alias that
requires another package directory. Internal build stages and compatibility
passthru attributes are allowed. Existing `apple-fonts.developerFonts` passthru
attributes remain available, while public developer-font outputs are independent.

Use `source.nix` for ordinary release pins. Use JSON manifests when the build
validates structured payload inventories. Keep existing SwiftPM `Sources/` and
`Tests/` conventions. Create subdirectories only when they clarify a larger
package. Small local helpers may be duplicated to preserve independent copying;
fixes to common logic should review all copies.

## Build contract

Use the upstream language and appropriate Nixpkgs builder. Data and prebuilt
applications use `stdenvNoCC`; native source uses the required compiler builder.
Set `strictDeps = true`, declare build tools in `nativeBuildInputs`, and target
libraries in `buildInputs`. Preserve phase hooks and use `--replace-fail` for
patch substitutions that depend on upstream text.

Keep build expressions local so package evaluation does not import a derivation
output. Evaluation checks disable import-from-derivation. Fetch immutable or versioned sources with verified content hashes. Keep network
access out of ordinary build phases. Minimize local source sets so editing a
README or updater does not needlessly rebuild compiled code. Record patches
and exceptional flags where they are applied.

Copy signed macOS vendor bundles without generic fixup. Modified or locally
compiled bundles need their explicit signing step. Test bundle files and
entrypoints without launching a GUI inside the build sandbox.

Provide a factual description, upstream homepage, license, platforms, and binary
provenance where applicable. Set `mainProgram` only for an installed executable.
Do not fabricate maintainer identities. Retain required upstream notices.

## Implementation languages

Use Nix for derivations, Bash for short build commands and wrappers, and Python
for source discovery, archive inspection and font transforms. Keep Swift for
native macOS utilities and their framework calls. Keep the existing CEF helper
in C because it interposes a C ABI and already has compiler and integration
checks. Rust is an option for new systems programs when its ownership model
solves a concrete problem; it is not a reason to rewrite existing packages.

Use structured parsers, checked subprocess argument lists and bounded network
requests in Python. Run Ruff formatting, lint and type checks. Preserve native
compiler warnings, sanitizers and package tests. Repository scripts orchestrate
these tools but are never imported by a package.

## Updates and verification

Updaters locate their source files relative to `__file__`, accept `--help`
without network access, and offer a preview before changing pins. Run a copied
package's updater with `python3 /path/to/package/update.py`. Nixpkgs-compatible
`passthru.updateScript` commands use editable paths from the repository root;
passing a single store copy of `update.py` would lose its helpers and metadata.
Font update wrappers additionally declare extraction and inspection tools.

Historical emoji releases and reviewed source compositions keep manual update
policies. Independent Apple developer font manifests also require manual source
and inventory review. A package without an updater must document that choice.

Run `just check`, `just lint`, and `just test`. The contract check evaluates
copied package directories with all personal dependency names poisoned, forces
metadata and derivation paths, and checks registry coverage. The layout check
rejects escaping symlinks and runs every updater's help from a temporary copy.
Python test modules run in separate processes to avoid collisions between local
module names such as `update` and `font_support`.

CI builds changed packages on matching Linux and macOS runners. Packaging or
check-infrastructure changes select every output. Both first-party Swift
packages run their quality suites and address/thread sanitizers. Build-time
checks do not establish GUI behavior, bit-for-bit reproducibility, or future
availability of upstream downloads; report those separately when relevant.
