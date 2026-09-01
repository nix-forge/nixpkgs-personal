#!@bash@
# shellcheck shell=bash
set -euo pipefail

repository_root="$(@git@ -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "error: run this command from a Git checkout of nixpkgs-personal" >&2
  exit 2
}

updater="$repository_root/scripts/update-packages.py"
if [[ ! -f $updater ]]; then
  echo "error: $repository_root is not a nixpkgs-personal checkout" >&2
  exit 2
fi

exec @python@ "$updater" "$@"
