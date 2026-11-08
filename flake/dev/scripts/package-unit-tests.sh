# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
export FONT_FIXTURE=@pkgs_dejavu_fonts@/share/fonts/truetype/DejaVuSans.ttf
export FONTCONFIG_FILE=@pkgs_by_name_ap_apple_fonts_fonts_conf@
export XDG_CACHE_HOME="$TMPDIR/cache"
python3 @unitSource@/tests/run_package_tests.py @unitSource@
python3 -B -m pytest -q -p no:cacheprovider @unitSource@/tests/test_update_packages.py @unitSource@/tests/test_package_catalog.py
touch "$out"
