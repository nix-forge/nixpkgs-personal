# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
export FONT_FIXTURE=@pkgs_dejavu_fonts@/share/fonts/truetype/DejaVuSans.ttf
export FONTCONFIG_FILE=@pkgs_by_name_ap_apple_fonts_fonts_conf@
export XDG_CACHE_HOME="$TMPDIR/cache"
cp -r @pkgs_lib_fileset_toSource_root_fileset_pkgs_lib_fileset_union@ source
chmod -R u+w source
python3 -B -m unittest discover -s source/pkgs/by-name/ap/apple-fonts -p test_fonts.py
python3 -B -m unittest discover -s source/pkgs/by-name/ap/apple-color-emoji -p test_update.py
python3 -B -m unittest discover -s source/pkgs/by-name/tt/ttf-ms-win11-auto -p test_manifest.py
touch "$out"
