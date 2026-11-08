# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
test -s "$out/Applications/FilmCraft.app/Contents/_CodeSignature/CodeResources"
python3 @tests_check_craft_assets_py@ plist "$out/Applications/FilmCraft.app/Contents/Info.plist" @upstreamVersion@
