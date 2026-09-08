# NUR support

The direct flake remains the primary interface. This repository also provides a
root `default.nix` accepting a caller-supplied `pkgs`, suitable for NUR and ordinary
Nix imports. It preserves the caller's Nixpkgs configuration and unfree policy.

The proposed NUR namespace is `nix-forge`. Registration has not been submitted.
Until NUR accepts it, use the direct flake or import this repository yourself.

```nix
let
  pkgs = import nixpkgs { system = "x86_64-linux"; };
  personal = import nixpkgs-personal { inherit pkgs; };
in personal.bibata-cursors-hyprcursor
```

After registration, the equivalent NUR attribute will be
`nur.repos.nix-forge.bibata-cursors-hyprcursor`. For an explicit NUR import:

```nix
let
  pkgs = import nixpkgs { system = "x86_64-linux"; };
  nurPackages = import nur { inherit pkgs; };
in nurPackages.repos.nix-forge.bibata-cursors-hyprcursor
```

Here `nixpkgs`, `nixpkgs-personal`, and `nur` are pinned source paths or flake inputs
supplied by the consumer. NUR membership does not make packages available on
unsupported platforms, audit their security, or grant redistribution permission.
Its search may omit unfree and macOS-only packages. The README is the collection's
full inventory.

## Compatibility and package policy

CI evaluates the entry point with the repository's locked Nixpkgs and current
`nixos-unstable`. Stable releases are not promised. Existing package names are a
public interface; incompatible renames should have a documented migration path.
Each package's README or description explains the personal variant where one
exists. Report compatibility problems through this repository's issues, including
the package name, system, repository revision and Nixpkgs revision.

Unfree packages require consumer consent. For example:

```nix
pkgs = import nixpkgs {
  inherit system;
  config.allowUnfreePredicate = package:
    builtins.elem (nixpkgs.lib.getName package) [ "ttf-ms-win11-auto" ];
};
```

Use the actual package `pname` when selecting other unfree packages. Evaluation
permission is separate from the upstream license's installation and distribution
terms. No cache publication is enabled by this NUR integration.

## Reproduce the checks

With Nix and Python 3 available, run:

```sh
python3 scripts/check-nur.py --nixpkgs locked --output /tmp/nur-locked
python3 scripts/check-nur.py --nixpkgs unstable --output /tmp/nur-unstable
```

The script fetches a pinned NUR evaluator and the requested Nixpkgs source before
restricted evaluation. It follows NUR's default unfree policy and 180-second
timeout, then separately evaluates supported derivation paths across all three
platforms with explicit unfree consent and import-from-derivation disabled.
Reports include the resolved Nixpkgs revision and NAR hash, including for the
moving unstable branch, plus package counts. CI reports also record the checked-out
repository revision. These are evaluation checks;
native build coverage remains in the existing CI matrix.

## Submission preparation

Publish the entry point, metadata and documentation, and wait for the NUR CI
matrix and existing package CI to pass on that published revision.

Review `docs/nur-registration.json` and add its entry to NUR's `repos.json`.
Confirm the proposed namespace remains available and format the manifest using
NUR's current instructions. Do not edit NUR's generated lock file.

Complete NUR's current PR checklist against the actual published package tree.
Retain all copyright notices and package-specific licenses. Submit only the
manifest change upstream.

The repository's own packaging code is covered by the root MIT license. Bundled
utilities retain their own MIT notices. Vendored expressions must retain their
upstream notices. Downloaded programs, fonts and artwork retain their upstream
licenses; the root MIT license does not relicense them. A license-notice review
does not independently establish every contributor's copyright ownership.

Sources: [NUR registration](https://github.com/nix-community/NUR#how-to-add-your-own-repository),
[submission checklist](https://github.com/nix-community/NUR/blob/main/.github/PULL_REQUEST_TEMPLATE.md),
[pinned evaluator](https://github.com/nix-community/NUR/blob/6e73a28249bbd53525bc1a7b385fcf3413c4e056/ci/nur/eval.py).
