set shell := ["/usr/bin/env", "bash", "-c"]

default:
    @just --list

check:
    nix store add-path flake/dev
    nix eval --option allow-import-from-derivation false --json .#checks --apply 'builtins.mapAttrs (_: checks: builtins.mapAttrs (_: check: check.drvPath) checks)' > /dev/null
    nix flake check --all-systems --no-build

test:
    nix store add-path flake/dev
    nix build --no-link .#checks.$(nix eval --impure --raw --expr builtins.currentSystem).package-independence .#checks.$(nix eval --impure --raw --expr builtins.currentSystem).package-policy .#checks.$(nix eval --impure --raw --expr builtins.currentSystem).package-unit-tests

fmt:
    nix fmt

lint:
    nix develop -c ruff format --check .
    nix develop -c ruff check .
    nix develop -c ty check

update-packages *args:
    nix develop -c python scripts/update-packages.py --all {{ args }}
