# Package standard

This repository uses the official guidance linked in [the research](package-design-research.md).
The additional independence requirement applies to every public output.

## Directory and dependency contract

Each public attribute has `pkgs/by-name/<first-two-letters>/<name>/package.nix`.
The expression is a function returning a derivation, with dependencies supplied
by upstream Nixpkgs. Keep its source pins, patches, helper modules, tests and
updater in that directory. Do not import sibling packages, repository tooling,
personal configuration modules, flake inputs, or a private Nixpkgs package set.

`pkgs/default.nix` discovers package directories and supplies the upstream scope.
Declare compatibility in each package's `meta.platforms` and, when needed,
`meta.badPlatforms`. Keep that metadata readable even on unsupported systems;
avoid a top-level platform assertion or throw that prevents reading it.
The registry remains lazy and includes all packages. The `packagesFor` helper
in `flake.nix` selects supported packages with `lib.meta.availableOn`. Flake
outputs use that set directly; the overlay uses its names, then instantiates
packages against the incoming scope. This avoids recursive metadata evaluation
and preserves upstream packages when a personal override is unsupported.
Adding a package requires no registry edit or separate platform list.

A public output must not be an alias that
requires another package directory. Internal build stages and compatibility
passthru attributes are allowed. The consolidated `apple-fonts` package keeps
its developer-distribution entries internal; it is the only public Apple
developer-font output.

Use `source.nix` for ordinary release pins. Use JSON manifests when the build
validates structured payload inventories. Keep existing SwiftPM `Sources/` and
`Tests/` conventions. Create subdirectories only when they clarify a larger
package. Small local helpers without an upstream equivalent may be duplicated to preserve independent copying;
fixes to common logic should review all copies.

## Build contract

Use the upstream language and appropriate Nixpkgs builder. Data and prebuilt
applications use `stdenvNoCC`; native source uses the required compiler builder.
Set `strictDeps = true`, declare build tools in `nativeBuildInputs`, and target
libraries in `buildInputs`. Preserve phase hooks and use `--replace-fail` for
patch substitutions that depend on upstream text.

For SwiftPM projects, take top-level `stdenv`, `swift`, and `swiftpm` inputs.
Use SwiftPM's build hook and pass compiler options through `swiftpmFlags`;
keep custom check or install phases when the package's products require them.
Use `fetchSwiftPMDeps` for locked external Git dependencies. Direct `swiftc`
builds need `swift` but not `swiftpm`. See the [pinned Swift packaging
research](swift-packaging-research.md) for the scope and exceptions.

Keep build expressions local so package evaluation does not import a derivation
output. Evaluation checks disable import-from-derivation. Fetch immutable or versioned sources with verified content hashes. Keep network
access out of ordinary build phases. Minimize local source sets so editing a
README or updater does not needlessly rebuild compiled code. Record patches
and exceptional flags where they are applied.

Fetch a package's own code from the repository where development happens when
that repository has a revision matching the packaged release. Compile generated
JavaScript, native addons, and other distributable code in the derivation.
Language package registries may supply locked build dependencies. If the current
release has no matching public source, record the gap and its non-source
provenance instead of presenting a registry artifact as a source build.

Copy signed macOS vendor bundles without generic fixup. Modified or locally
compiled bundles need their explicit signing step. Test bundle files and
entrypoints without launching a GUI inside the build sandbox.

Provide a factual description, upstream homepage, license, platforms, and binary
provenance where applicable. Set `mainProgram` only for an installed executable.
Do not fabricate maintainer identities or retain inherited ownership of a modified
expression without consent. Retain required upstream notices.

For a macOS application, set `mainDarwinApp` to the exact installed directory
under `Applications`, including `.app`. Gate this field for callers older than
Nixpkgs 26.11. Keep a separate `mainProgram` only when the output installs a
command in `bin`. Preserve signed vendor plists; validate identities, executables
and icons in package-local install checks. Locally authored plists use a
structured writer and the actual platform deployment minimum.

Use `makeDesktopItem` and `copyDesktopItems` for newly authored Linux launchers.
Preserve accurate upstream desktop IDs, translations, MIME associations and
AppStream assets. Validate installed entries after patching, and verify that
`Exec`, `TryExec` and `Icon` resolve to the packaged command and artwork. Add
optional startup or D-Bus metadata only with evidence of application support.
See the [application metadata research](package-metadata-research.md#application-metadata-review-2026-10-12).

Review the license of every bundled component, including per-skill terms and
font assets. A mixed license list must include restricted components; public
source code alone does not establish a free license. Use `binaryBytecode` for
prebuilt fonts, `binaryNativeCode` for vendor executables, and `fromSource` for
locally compiled code or supplied source text. A catalog containing source text
and prebuilt fonts needs both provenance values.

Keep unfree policy in the consuming Nixpkgs import. Restricted source fetchers
should have stable `pname` values so a package-name predicate can allow them.
Composite font packages also require consent for their constituent packages.
Do not add speculative `broken`, vulnerability, maintainer or redistribution
metadata. Preserve upstream fields only while they remain accurate for the
variant, including update scripts. See the [metadata research](package-metadata-research.md).

## Native helpers and hook files

Use upstream Nixpkgs helpers through explicit function arguments. Prefer
`writeShellApplication` for an installed Bash command that needs runtime inputs
and ShellCheck. Its default strict shell options change execution semantics, so
review them before converting an existing command. Use `writeShellScriptBin`
when a small wrapper intentionally needs different shell behavior and supplies
its dependencies explicitly.

Use `writers.writePython3Bin` for one executable Python source file. Declare
Python libraries with `libraries`, pass the local source path directly, and keep
its default checks. Use `buildPythonApplication` for Python distributions and
`buildPythonPackage` for importable libraries. Keep multi-file applications,
relative assets and upstream build systems in their language builders.

Render package-local hook templates with `replaceVars`, then source the result
in the existing build shell:

```nix
installPhase = ''
  source ${replaceVars ./scripts/install-phase.sh {
    helper = lib.escapeShellArg (lib.getExe helper);
  }}
'';
```

Sourcing preserves phase functions, arrays, variables and directory changes.
The hook file still calls its corresponding `runHook` functions. Do not execute
phase fragments in a child shell or read the generated file during evaluation.
`replaceVars` validates replacements when it builds, including unresolved tokens
introduced by replacement values. Use `null` for a literal token already in the
input. For deferred output-path substitution, split the literal token in the
shell source so only the install step constructs it.

When a writer needs source text for its own checks, use `lib.replaceStrings`
over `builtins.readFile` of a local template and assert that all intended tokens
are present and resolved. Keep quoting appropriate to the destination language.
Avoid copying repository-specific rendering helpers into package folders.
See the [native helper research](package-design-research.md#native-helpers-review).

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
without network access, and offer a preview before changing pins. Each updater
has a package-local `update.nix` built with `writeShellApplication`; declare its
Python libraries, Nix, certificates, and any Git, extraction or inspection tools.
Keep updater dependencies separate from the application closure.

The daily scheduled runner discovers these entry points and runs each in a
separate checkout. Each changed package gets its own signed commit, branch,
pull request, and required CI runs. A failed updater stops only its package
job. The pull request enters the merge queue after its checks pass; failed
checks leave that package's pull request open for review.

Expose the native command and editable source directory as separate arguments
in `passthru.updateScript`. The upstream runner rewrites checkout paths into its
temporary worktree. Do not bake a writable checkout path into the wrapper body.
The launcher accepts `--package-dir` or `UPDATE_NIX_PACKAGE_DIR` for an explicit
editable folder, and otherwise discovers the package in the caller's checkout.
Store copies are never editing targets. Direct
`python3 /path/to/package/update.py` remains supported with the required tools.

Dependency refreshers use `NIXPKGS_UPDATE_SOURCE` from the native wrapper.
Standalone Python refreshers use `NIX_PATH`, or a documented explicit selector.
Do not derive a personal flake from fixed directory ancestry. Stage candidate
sources and dependency files before publishing. Replace related files with
unique sibling temporary files, preserve permissions and roll back ordinary
write failures. This does not promise recovery after power loss or `SIGKILL`.
Keep scripts free of Git commits and omit upstream commit feature declarations
unless their required JSON protocol is implemented.

Keep ordinary version, revision and SHA-256 SRI pins in `source.nix`. JSON
inventories, NuGet dependency graphs and upstream lockfiles retain their
structured formats. Match flat download hashes and recursive unpacked hashes
to the actual fetcher. Refresh dependencies with the selected release and
existing toolchain; an application update must not silently upgrade dependency
ranges. See the [updater and pin review](package-update-automation-research.md#updater-and-release-pin-review-2026-10-12).

Source compositions can use an updater when it refreshes every pinned input
from the same selected release and stops on ambiguous compatibility metadata.
The scheduled runner can submit successful updates after another updater fails
only when the failed updater left the working tree unchanged. Historical emoji
releases and the consolidated Apple developer-font entries still require manual
source and inventory review. A package without an updater must document that
choice.

Run `just check`, `just lint`, and `just test`. The contract check evaluates
copied package directories with all personal dependency names poisoned, forces
metadata on all systems and derivation paths on supported systems, and checks
registry coverage. It also evaluates the overlay and checks that its names
match supported packages, preventing recursion and unsupported overrides. The template check builds native hook substitutions and parses their generated
Bash without building the applications. Helper regressions exercise sourcing,
quoting, runtime inputs and Python libraries. The layout check
rejects escaping symlinks and runs every updater's help from a temporary copy.
The source-pin check validates non-placeholder SRI hashes and rejects common
moving branch and release names in `source.nix`; package-local validators check structured inventories.
The updater check runs all native commands from standalone editable copies with
an empty caller PATH and tests source-directory arguments. Transaction and
dispatcher tests cover rollback, file modes and changes to already dirty files.
Python test modules run in separate processes to avoid collisions between local
module names such as `update` and `font_support`.
Metadata validation uses `checkMeta = true`. The package-policy check exercises
default unfree rejection, selective package-name consent and source provenance
through the public import and overlay interfaces on all supported flake systems.

CI evaluates all packages and builds eligible changed packages on matching Linux
and macOS runners. The reasoned exclusions in `.github/ci-policy.json` govern
hosted builds; see [the licensing policy](package-licensing.md#hosted-builds).
Packaging or check-infrastructure changes select every output. Both first-party Swift
packages run their quality suites and address/thread sanitizers. Build-time
checks do not establish GUI behavior, bit-for-bit reproducibility, or future
availability of upstream downloads; report those separately when relevant.
