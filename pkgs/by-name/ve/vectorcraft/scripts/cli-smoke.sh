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
printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16" fill="red"/></svg>' >input.svg
@package@/bin/vectorcraft-cli convert input.svg rendered.png
python3 @tests_check_craft_assets_py@ png rendered.png
