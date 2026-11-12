# Package design research

Reviewed 2026-09-07 against the official sources linked below. These recommendations apply to `nixpkgs-personal`, including its package definitions, bundled programs, and update tools. They describe the intended standard; this document alone is not evidence that every build or interactive application was tested.

## Package boundaries and file layout

Keep `pkgs/by-name/<first-two-letters>/<attribute-name>/package.nix`. Nixpkgs uses this structure for top-level packages and requires a function that returns a derivation. Additional files belong inside the package directory. Its by-name checks prohibit references to files outside that directory. [Nixpkgs by-name rules](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/README.md)

Use this shape when a package needs the corresponding files. Small packages do not need empty subdirectories.

```text
pkgs/by-name/fo/foo/
  package.nix
  source.nix
  update.py
  README.md
  tests.nix
  patches/
  <package-local helpers and application sources>
```

The names `source.nix`, `update.py`, and `patches/` are project conventions. Preserve Swift's `Package.swift`, `Sources/`, and `Tests/` layout and Rust's `Cargo.toml`, `Cargo.lock`, and `src/` layout instead of renaming application files to force uniformity. Swift Package Manager models executable, library, and test targets within a package. [Swift Package Manager reference](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html)

Our stronger project rule is that a package can be copied out with its own directory and instantiated against the supported upstream Nixpkgs pin. Build, runtime, tests, and package update tools must not require a sibling personal package or repository-root Python module. Upstream Nixpkgs normally allows package dependencies. The additional restriction comes from this project's independence requirement.

Keep repository-wide CI, formatting, discovery, and batch-update orchestration outside package directories. These tools may invoke packages; packages must not import them. Small duplicated support files are an acceptable cost of independent copying. Keep duplicates narrow and use repository checks to detect unintended divergence.

Use `lib.packagesFromDirectoryRecursive` with an upstream-only `callPackage`
to discover the package directories, then flatten the two-letter prefix groups.
Omit `newScope`, which would let discovered packages resolve each other as
dependencies. The helper stops at a directory's `package.nix`, keeping internal
Nix files private. [Nixpkgs directory discovery implementation](https://github.com/NixOS/nixpkgs/blob/master/lib/filesystem.nix)

Keep the registry lazy, as in Nixpkgs. Declare supported platforms
inside each package and select flake `packages.<system>` with
`lib.meta.availableOn`, which respects both `meta.platforms` and
`meta.badPlatforms`. Metadata does not automatically filter flake outputs.
The overlay uses the same selection to choose names, then instantiates those
packages against its incoming scope. Reading platform metadata from those
overlay values would force dependencies while Nixpkgs is still constructing its
recursive package set. Selecting names against the flake's plain Nixpkgs input
avoids that cycle and keeps unsupported overrides from replacing upstream
packages, such as Steam on Linux. Packages must let callers read platform
metadata without first throwing on an unsupported host. OS-specific build
recipes may still use a conditional inside the package.
[Nixpkgs platform predicate](https://github.com/NixOS/nixpkgs/blob/master/lib/meta.nix)

## Dependency injection and overlays

List dependencies as function arguments and instantiate with `callPackage`. This exposes dependencies and preserves `.override` without importing Nixpkgs or a flake from inside a package. [nix.dev callPackage tutorial](https://nix.dev/tutorials/callpackage.html)

For this collection, explicitly resolve package arguments against the incoming upstream scope. The ordinary overlay model resolves dependencies through the final scope so other overlays can replace them. That can accidentally connect personal packages when names overlap, such as `steam`. Independence therefore deliberately trades some overlay-wide replacement behavior for predictable upstream dependencies. Document this choice and preserve explicit package overrides. [Nixpkgs overlays](https://nixos.org/manual/nixpkgs/stable/#chap-overlays)

Use `lib.callPackageWith pkgs` when a fixed incoming scope is required. Merely using an inherited `callPackage` is not sufficient evidence that its automatic argument scope excludes final overlay values. Avoid a recursive scope that combines upstream and personal outputs.

Cross compilation also requires Nixpkgs' build/host dependency variants. Use
`pkgs.splicePackages` with the incoming set as `pkgsHostTarget`, then retain
Nixpkgs' unspliced package-set arguments before constructing `callPackageWith`.
This preserves native behavior and lets `nativeBuildInputs` select build tools
when an overlay supplies an unspliced incoming set. Adjacent build-stage sets
remain those supplied by the caller.
[Pinned splicing implementation](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/top-level/splice.nix)

Avoid comparing derivation output paths when filtering cross build tools. The
Noctalia allocator override now compares package names: derivation equality
forced the target-side `makeWrapper` before Nixpkgs could select its build-side
variant. Regression evaluation covers the real recipe copied out of its folder,
the registry and an incoming overlay scope without building ARM programs.

Aliases may remain for compatibility, but any output promised as an independently copyable package needs its own package directory. A package may build internal components or expose passthru information without creating a dependency on another public personal package.

## Build and metadata standards

Use immutable revisions or versioned releases with real content hashes. Prefer fetchers appropriate to the source. A hash detects changed bytes; it cannot prevent an upstream server removing an old release. Keep network discovery in update tools and network downloads in fixed-output fetchers. [Nixpkgs fetcher documentation](https://github.com/NixOS/nixpkgs/blob/master/doc/build-helpers/fetchers.chapter.md)

Use `stdenvNoCC` for copying assets or installing prebuilt applications. Use the language-specific builder when compilation needs it. Put build tools in `nativeBuildInputs` and target libraries in `buildInputs`. Preserve standard phases and invoke the corresponding pre/post hooks in custom phases. Document patches, unusual flags, and disabled checks. [Nixpkgs package review checklist](https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md#reviewing-contributions)

Each package should provide a factual one-line description, upstream homepage, accurate license and platforms. Set `mainProgram` only when an executable exists. Mark downloaded native binaries with `lib.sourceTypes.binaryNativeCode`. An empty maintainer list is not meaningful ownership; use a real agreed maintainer identity, never an invented one. Preserve upstream attribution and license files in outputs where required. [Nixpkgs metadata reference](https://github.com/NixOS/nixpkgs/blob/master/doc/stdenv/meta.chapter.md)

Builds should succeed in the sandbox with declared inputs, without reading a checkout, user home, or installed application. Some macOS frameworks require system resources; document those narrow requirements and test on macOS. Sandbox isolation does not itself prove bit-for-bit reproducibility. [Nix sandbox configuration](https://nix.dev/manual/nix/stable/command-ref/conf-file.html#conf-sandbox)

For prebuilt signed macOS applications, preserve the vendor bundle rather than running generic fixup over it. Apple documents that post-signing changes invalidate signatures and that signed bundles should be treated as read-only. Locally compiled or patched applications need their explicit signing step after modifications. [Apple code signing tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)

## Language choices

There is no universal best language for this collection. These are project choices based on what the programs do and the existing code.

| Work | Default | Reason and practice |
| --- | --- | --- |
| Derivations and dependency wiring | Nix | Keep declarative package logic in the package expression |
| Short command wrappers and build phases | Bash | Appropriate for invoking tools; use ShellCheck and quote expansions |
| Update discovery, manifests, archive inspection, font data transformations | Python | Use structured parsers and explicit errors; call subprocesses with argument lists, checked exit status, and suitable timeouts |
| Existing native macOS utilities | Swift | Keep direct use of macOS APIs and the existing Swift package and test structure |
| Existing narrow C ABI helpers | C | Keep the small interposition library, explicit exported symbols and integration tests |
| Existing systems programs or new services needing tight resource control | Rust | Ownership checks provide memory safety without a garbage collector; the compiler and dependency maintenance cost needs a concrete benefit |

Google's shell guide recommends shell for small wrappers and a structured language for complicated control flow. Its length threshold is a Google convention, not a Nixpkgs requirement. [Google shell guide](https://google.github.io/styleguide/shellguide.html#when-to-use-shell)

Prefer `writeShellApplication` for installed wrappers. It supplies runtime dependencies, Bash syntax checks, ShellCheck, and strict Bash options. [Nixpkgs shell application helper](https://nixos.org/manual/nixpkgs/stable/#trivial-builder-writeShellApplication)

Python's subprocess API supports argument lists, `check=True`, and timeouts. Avoid `shell=True` when invoking tools with discovered filenames or release metadata. [Python subprocess reference](https://docs.python.org/3/library/subprocess.html)

Rust's ownership model is a reason to choose it for suitable systems work, not evidence that rewriting working Python or Swift improves this repository. Retain upstream implementation languages when packaging third-party software. [Rust ownership chapter](https://doc.rust-lang.org/book/ch04-01-what-is-ownership.html)

## Verification and update policy

Run upstream unit tests during `checkPhase` where supported. Use installation checks for basic executable or asset validation. Put consumer-facing checks in `passthru.tests`, then explicitly expose or run them in CI. Merely defining passthru tests does not guarantee they run with a normal package build. [Nixpkgs passthru test documentation](https://github.com/NixOS/nixpkgs/blob/master/doc/stdenv/passthru.chapter.md)

For this project, verify independence by copying each directory and evaluating it with a clean upstream package scope. Inspect required function arguments, symlink escapes, and runtime references as well. Source-text scanning alone cannot prove dependency isolation. Validate output metadata for every supported system; build applicable packages on actual compatible builders. Record unavailable builders and GUI checks as validation limits.

Package update tools should locate files relative to themselves, accept `--help` without network access, validate upstream metadata before writing, and change only their own pinned files. Expose conventional `passthru.updateScript` where practical. Keep reviewed historical versions explicitly excluded from automatic updates. The standard updater entrypoint is documented by Nixpkgs; the stricter write boundary is this project's policy. [Nixpkgs automatic update conventions](https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md#automatic-package-updates)

## Native helpers review

Reviewed 2026-10-12 against the current official sources and repository pin
`151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4`. The question was whether native helpers
could replace local writers and renderers while each package remains copyable.

Use each helper for its intended artifact:

| Artifact | Helper | Relevant behavior |
| --- | --- | --- |
| Installed Bash command | `writeShellApplication` | Runtime inputs, strict Bash options, syntax checks and ShellCheck |
| Minimal Bash wrapper | `writeShellScriptBin` | Shebang and syntax checks; declare dependencies explicitly |
| One executable Python file | `writers.writePython3Bin` | Local source path, Python libraries and default flake8 checks |
| Python application or library distribution | `buildPythonApplication` or `buildPythonPackage` | Upstream Python build metadata and dependency hooks |
| Build-consumed template | `replaceVars` | Validates unused and unresolved substitutions, allows named literal tokens with `null` |
| Evaluation-time source text | `lib.replaceStrings` | Pure substitution; assertions must supply token validation |

These behaviors come from the [pinned shell builders](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/build-support/trivial-builders/default.nix),
[pinned Python writers](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/build-support/writers/scripts.nix),
[Python packaging guide](https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/python.section.md),
and [replacement implementation](https://github.com/NixOS/nixpkgs/blob/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4/pkgs/build-support/replace-vars/replace-vars-with.nix).

For hook fragments, source the generated `replaceVars` output in the stdenv
shell. This preserves `runHook`, arrays, variables and directory changes.
Calling a writer or `bash` would start a separate process. Reading the generated
output with `builtins.readFile` would require import-from-derivation, which
Nixpkgs prohibits. This recommendation follows from the
[standard environment lifecycle](https://github.com/NixOS/nixpkgs/blob/master/doc/stdenv/stdenv.chapter.md)
and the helper's derivation output.

Replacement values still need destination-language quoting. Native substitution
also rejects unresolved tokens introduced by a replacement. Steam and Scrypted
fill their launcher's output path during installation, so their shell fragments
construct that deferred token from separate shell string parts. The launcher that
uses `writeShellApplication` keeps pure source rendering so the writer checks
the complete body.

The implementation replaces the duplicated package renderers with upstream
helpers and retains package-local sources and the clean dependency scope.
Local TypeScript packages use `lib.fileset.toSource` to exclude recipe and
documentation changes from their build sources.
The generated-template check removes application dependencies only from its
validation copies, then builds the real native substitutions and checks Bash
syntax. Production recipes keep every dependency context. The helper regression
check exercises shared shell state, phase hooks, argument quoting, a restricted
runtime PATH and a Python library import.

Directory independence reduces the work of preparing a submission. Upstream
still requires real maintainership, and its contributor guidance discourages
new `overrideAttrs` variants. Existing personal variants may need to become
options or changes to their original packages. Native helpers alone do not
establish upstream acceptance. See the
[by-name rules](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/README.md)
and [contributor guidance](https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md).

Implementation validation used a private source snapshot of the working tree.
`just check` evaluated all three exported systems with import-from-derivation
disabled. `just test` passed the package copy/metadata/overlay and consumer-policy
checks on `aarch64-darwin`. `just lint` passed Python formatting, Ruff and type
checks. Native Darwin builds passed the helper regressions, Firefox Emoji,
the MetaBrainz extension and T3's runtime-check TypeScript package. The consuming
desktop system's complete derivation also evaluated successfully against the
working package sources.

The template check can inspect another system's recipes using the pinned native
renderer. Its source text contains the target's dependency paths, but the check
builds only substitutions and validates syntax. This permits Linux-specific
hook coverage on a Darwin host without compiling target applications. All three
source matrices built and passed on the native Darwin renderer:

| Recipe system | Bash templates | Python templates |
| --- | --- | --- |
| `x86_64-linux` | 514 | 1 |
| `aarch64-linux` | 502 | 0 |
| `aarch64-darwin` | 464 | 0 |

Counts include separately instantiated font variants and nested helper files.
Linux application builds and the Linux-only package tooling unit suite were not
run in this validation.

These results cover evaluation, generated sources and the named builds. They
do not establish native builds of every application or interactive GUI behavior.
