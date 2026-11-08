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
@package@/bin/gridcraft-cli eval '=SUM(1,2,3)' --json >result.json
python3 @scripts_package_check_pyjson_py@
printf 'item,amount\npens,6\n' >input.csv
@package@/bin/gridcraft-cli convert input.csv workbook.xlsx
@package@/bin/gridcraft-cli convert workbook.xlsx roundtrip.csv
python3 @scripts_package_check_pycsv_py@
