# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
python3 @tests_check_package_layout_py@ @value@
python3 -B @value@/tests/test_package_layout.py
python3 -B @value@/tests/test_nur_check.py
cp "$reportPath" "$out"
