# shellcheck shell=bash
# Nix renders immutable dependency sources and their provenance metadata.
# The Nix builder supplies out.
# shellcheck disable=SC2154
mkdir -p "$out/share/doc/@pname@/licenses/git"
install -Dm644 @gitMetadata@ "$out/share/doc/@pname@/licenses/git/sources.json"
dependencies=(@gitSources@)
for dependency in "${dependencies[@]}"; do
  destination="$out/share/doc/@pname@/licenses/git/$(basename "$dependency")"
  mkdir -p "$destination"
  # Cargo workspace member copies omit repository-root license and notice files.
  for notice in "$dependency"/LICENSE* "$dependency"/COPYING* "$dependency"/NOTICE* "$dependency"/ATTRIBUTION*; do
    if [[ -f $notice ]]; then
      install -Dm644 "$notice" "$destination/$(basename "$notice")"
    fi
  done
  test -s "$destination/LICENSE-MIT"
  test -s "$destination/LICENSE-APACHE"
done
