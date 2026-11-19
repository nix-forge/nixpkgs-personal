# Build using the host's configured compiler parallelism.
task := ""

set shell := ["/usr/bin/env", "bash", "-c"]

default:
    @just --list

check:
    bash scripts/check-flake.sh

# Run only the Nix library suite.
test:
    nix store add-path flake/dev
    nix build --no-link .#checks.$(nix eval --impure --raw --expr builtins.currentSystem).lib-tests

fmt:
    nix fmt

lint:
    nix develop -c ruff format --check .
    nix develop -c ruff check .
    nix develop -c ty check

update-packages *args:
    nix develop -c python scripts/update_packages.py --all {{ args }}
