# Swift packaging in pinned Nixpkgs

Reviewed: 2026-10-06. Scope: Swift recipes in nixpkgs-personal against its
`nixpkgs` input, `c59305bab2065cfecc4944690d9eedbb56f3a9fa`.

## Answer

The pinned Nixpkgs input has the Swift 6.2.4 packaging rewrite. Its current
recipe for a SwiftPM project is `stdenv.mkDerivation` with `swift` and `swiftpm`
in `nativeBuildInputs`. SwiftPM is a separate package: `swift` supplies the
compiler, while `swiftpm` propagates setup hooks for the default release build,
optional test phase, product installation, and vendored dependency setup. The
preferred source dependency fetcher is `fetchSwiftPMDeps` when a project has a
`Package.resolved` with Git pins. `swiftpm2nix` remains supported. These are
observations from the [pinned Swift manual](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/doc/languages-frameworks/swift.section.md)
and [pinned release notes](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/doc/release-notes/rl-2611.section.md).

The rewrite does not require converting a project that deliberately invokes
`swiftc` directly into SwiftPM. The manual explicitly covers custom build tools,
and only promises SwiftPM phases when `swiftpm` is included. Keep a direct
compiler recipe when its source/build design calls for one, but use the current
`swift` compiler package and explicit compiler flags. This is an inference from
the [manual's custom-build-tool section](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/doc/languages-frameworks/swift.section.md#considerations-for-custom-build-tools-ssec-swift-considerations-for-custom-build-tools)
and the local package sources.

## Findings and sources

- The [pinned scope](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/pkgs/top-level/swift-packages.nix)
  assigns its `stdenv` to `clangStdenv`, has Swift 6.2.4, and retains a few
  compatibility aliases for old names. The [top-level exports](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/pkgs/top-level/all-packages.nix#L4080-L4090)
  include `swift`, `swiftpm`, `fetchSwiftPMDeps`, and `swiftpm2nix`. Prefer those
  public package arguments in new recipes. The old `swiftPackages.stdenv` is
  still a scope member; its mere presence is not proof that existing code is
  broken.
- The [SwiftPM hook](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/pkgs/development/compilers/swift/by-name/sw/swiftpmHook/setup-hook.sh)
  runs `swift build --disable-sandbox` with release configuration by default,
  passes parallelism and a module-cache path, and exposes `swiftpmFlags`,
  `swiftpmFlagsArray`, and `swiftpmBuildConfig`. It supplies `swift test` when
  `doCheck = true`, `swiftpmBinPath` for custom installation, and an install
  phase that reads declared executable and library products. Explicit
  `buildPhase`, `checkPhase`, or `installPhase` takes precedence over its
  corresponding default. `dontUseSwiftpmBuild`, `dontUseSwiftpmCheck`, and
  `dontUseSwiftpmInstall` disable the respective hook phases.
- A local Darwin build showed that a Nix list assigned to `swiftpmFlagsArray`
  became one escaped shell value, so SwiftPM received all flags as a single
  invalid option. The hook expects an actual Bash array for that variable;
  [`concatTo` in stdenv](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/pkgs/stdenv/generic/setup.sh#L429-L456)
  treats a scalar named `*Array` as a singleton. For fixed package flags,
  `swiftpmFlags` works as a space-separated string; the final native build
  verified that path.
- The [unpack hook](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/pkgs/development/compilers/swift/by-name/sw/swiftpmUnpackHook/setup-hook.sh)
  consumes `swiftpmDeps`. The [fetcher](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/pkgs/development/compilers/swift/by-name/fe/fetchSwiftPMDeps/package.nix)
  requires `src` and `hash`, supports `sourceRoot`, `patches`, and `postPatch`,
  and rejects non-Git dependency pins. It reads `Package.resolved`; projects
  without a shipped lock file must supply one. A pinned [Nixpkgs example](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/pkgs/by-name/ag/age-plugin-se/package.nix)
  passes `inherit (finalAttrs) pname version src` to the fetcher.
- The [release notes](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/doc/release-notes/rl-2611.section.md)
  say `swift` is no longer wrapped and `NIX_SWIFTFLAGS_COMPILE` is unsupported.
  Compiler flags must go through the build system. SwiftPM itself no longer
  carries Git for runtime dependency fetching; add Git to development
  environments that need it. This is separate from vendoring dependencies in
  Nix derivations.
- The [manual](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/doc/languages-frameworks/swift.section.md#considerations-for-custom-build-tools-ssec-swift-considerations-for-custom-build-tools)
  defines `stdenv.<platform>.swift.{platform,arch,triple}` for target-aware
  custom builds. On Darwin, the Swift triple includes the deployment target.
  The compiler toolchain includes its core libraries, so a normal application
  does not add Foundation, Dispatch, XCTest, or Swift Testing individually.

## Implication for this repository

The Swift recipe inventory under `pkgs/by-name/` has three packages:

| Package | Current build | Migration decision |
| --- | --- | --- |
| [`finder-favorites`](../pkgs/by-name/fi/finder-favorites/package.nix) | SwiftPM with a release-built self-test and custom install phase | Use public `stdenv`, `swift`, and `swiftpm` arguments. Pass compiler diagnostics through `swiftpmFlags` and use the hook's build phase. Keep the custom self-test and install phases so the test executable is not installed. Preserve deployment metadata and signing. The [pinned manifest](https://github.com/IanHollow/finder-favorites/blob/d35623e32ee6597d2018dd0d9c80ecb09db360cf/Package.swift) declares local targets and no external package dependencies; `fetchSwiftPMDeps` is unnecessary at this source revision. |
| [`ocr-capture`](../pkgs/by-name/oc/ocr-capture/package.nix) | Direct `swiftc` compilation with an SDK feature probe | Keep the direct build and explicit target/compiler flags. It has no SwiftPM invocation, so a `swiftpm` dependency and SwiftPM phases add no value. |
| [`vorssaint`](../pkgs/by-name/vo/vorssaint/package.nix) | Direct `swiftc` compilation of app, helper, and adapter | Keep the upstream-style direct build and explicit target/compiler flags. Its package comment explains this choice; it does not use SwiftPM phases. |

For future SwiftPM packages, start with `stdenv.mkDerivation (finalAttrs: { ... })`,
`nativeBuildInputs = [ swift swiftpm ];`, and `swiftpmDeps = fetchSwiftPMDeps {
inherit (finalAttrs) pname version src; hash = "..."; };` when external Git
dependencies are locked. Enable `doCheck` when SwiftPM tests can run. Let the
hook handle phases until a verified package requirement calls for an override;
when installing a special output, locate it with `swiftpmBinPath`. These
choices follow the [manual](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/doc/languages-frameworks/swift.section.md#packaging-with-swiftpm-ssec-swift-packaging-with-swiftpm)
and the [pinned example](https://github.com/NixOS/nixpkgs/blob/c59305bab2065cfecc4944690d9eedbb56f3a9fa/pkgs/by-name/ag/age-plugin-se/package.nix).

## Validation and limits

Read the locked input at the revision above and inspected its manual, release
notes, scope, hook scripts, fetcher, and example recipe on 2026-10-06. A local
Nix evaluation of that input returned `swift.version = 6.2.4` on
`x86_64-linux`. Inspected the three local Nix package definitions and the
Finder Favorites manifest at its pinned source commit.

After the migration, `just check`, `just lint`, and `just test` passed in the
package repository on `x86_64-linux`; `just check` was rerun after the final
SwiftPM hook edit. All three packages built on `aarch64-darwin`, including
their package self-tests and install checks. The root integration's focused
temporary-fix evaluation passed on Linux for Darwin package selection, and
the macOS `swift-hardening` check and selected package builds succeeded.
This verifies native builds and package checks, not GUI behavior or activation.
