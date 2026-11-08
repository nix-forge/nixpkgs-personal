# Desktop heavy work shares the project workload queue.
task := if os() == "linux" { if `hostname -s` == "desktop" { "workstation-task" } else { "" } } else { "" }

set shell := ["/usr/bin/env", "bash", "-c"]

default:
    @just --list

check:
    {{ task }} bash scripts/check-flake.sh

test:
    #!/usr/bin/env bash
    set -euo pipefail
    nix store add-path flake/dev
    system="$(nix eval --impure --raw --expr builtins.currentSystem)"
    checks=(".#checks.$system.source-pins" ".#checks.$system.package-updaters" ".#checks.$system.updater-unit-tests" ".#checks.$system.package-app-metadata" ".#checks.$system.package-independence" ".#checks.$system.package-policy" ".#checks.$system.package-templates" ".#checks.$system.package-helpers")
    # Architecture-neutral tooling tests are exported once, on x86_64-linux.
    if [[ "$system" == "x86_64-linux" ]]; then
        checks+=(".#checks.$system.package-unit-tests")
    fi
    {{ task }} nix build --no-link "${checks[@]}"

fmt:
    nix fmt

lint:
    {{ task }} nix develop -c ruff format --check .
    {{ task }} nix develop -c ruff check .
    {{ task }} nix develop -c ty check

update-packages *args:
    {{ task }} nix develop -c python scripts/update_packages.py --all {{ args }}
