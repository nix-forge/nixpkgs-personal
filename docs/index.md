# nixpkgs-personal

This repository publishes maintained Nix packages through a flake and an overlay.
Start with the [package catalog](catalog.md) to find a package and its supported
platforms. The [usage guide](nur.md) shows the direct flake interface and the
current NUR status.

Package recipes live under `pkgs/by-name/`. A package-specific README documents
behavior that does not belong in the catalog. The
[package standard](package-standard.md) defines the common interface and review
rules. Licensing decisions remain in the
[licensing policy](package-licensing.md).

The website contains the stable package and maintenance documentation. Source,
package-level notes, checks, and release history remain in the
[GitHub repository](https://github.com/nix-forge/nixpkgs-personal).

## Use a package

Build a package without adding the repository to a configuration:

```console
nix build github:nix-forge/nixpkgs-personal#PACKAGE
```

Pin the flake input before using a package in a system or home configuration.
The repository's `flake.lock` pins development and validation dependencies; it
does not pin a downstream consumer's input for them.

## Maintain the documentation

Build the exact site artifact used by CI:

```console
nix build .#checks.x86_64-linux.documentation-site
```

Preview documentation while editing:

```console
nix develop .#docs --command mkdocs serve --config-file site/mkdocs.yml
```

MkDocs treats missing pages and anchors as build failures. Links to source files
outside `docs/` stay on GitHub and are not copied into the site.
