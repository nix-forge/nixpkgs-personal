# shellcheck shell=bash
# Variables and functions are supplied by the owning activation or build phase.
# shellcheck disable=SC2154
themeRoot="$out/share/icons/@theme@"
test -s "$themeRoot/manifest.hl"
test -s "$themeRoot/index.theme"
test -d "$themeRoot/hyprcursors"
test -d "$themeRoot/cursors"
test -e "$themeRoot/cursors/left_ptr"
test "$(find "$themeRoot/hyprcursors" -name '*.hlc' -type f | wc -l)" -gt 0
