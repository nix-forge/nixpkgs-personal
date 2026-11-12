# shellcheck shell=bash
# Retain icons referenced by existing user-owned autostart entries.
set -euo pipefail
output=$1
desktop_id=$2
legacy_id=io.github.nix-forge.craft-launcher
ln -s "$desktop_id.svg" "$output/share/icons/hicolor/scalable/apps/$legacy_id.svg"
for size in 64 256; do
  ln -s "$desktop_id.png" "$output/share/icons/hicolor/${size}x${size}/apps/$legacy_id.png"
done
