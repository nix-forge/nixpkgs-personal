# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
export HOME="$TMPDIR"
# These notices are required for the default fonts embedded by egui.
for notice in "@package@/share/doc/@pname@/licenses/dependencies"/epaint_default_fonts-*/fonts/{OFL,UFL,Hack-Regular}.txt; do
  test -s "$notice"
done
@darwinCliCheck@
@package@/bin/@pname@-cli --version >"$out"
@package@/bin/@pname@-cli commands >commands.txt
test -s commands.txt
@package@/bin/lightcraft-cli snapshot --demo -o rendered.png --size 320x240
python3 @tests_check_craft_assets_py@ png rendered.png
