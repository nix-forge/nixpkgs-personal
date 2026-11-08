# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
export XDG_CACHE_HOME="$TMPDIR/font-cache"
export FONTCONFIG_FILE=@fonts_conf@
python3 @builder@/unpack_font_distribution.py "$src" @fontManifest@ "$out"
install -Dm444 @readme@ "$out/share/doc/@entry_name@/PACKAGING.md"
install -Dm444 @licenseScope@ "$out/share/doc/@entry_name@/license-scope.json"
runHook postInstall
