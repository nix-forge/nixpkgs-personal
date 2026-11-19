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
  licenseFound=0
  for notice in "$dependency"/LICENSE* "$dependency"/COPYING* "$dependency"/NOTICE* "$dependency"/ATTRIBUTION*; do
    if [[ -f $notice ]]; then
      test -s "$notice"
      install -Dm644 "$notice" "$destination/$(basename "$notice")"
      case "$(basename "$notice")" in
      LICENSE* | COPYING*) licenseFound=1 ;;
      esac
    fi
  done
  # Git dependencies may use one Apache, BSD, or other declared license file.
  test "$licenseFound" -eq 1
done
