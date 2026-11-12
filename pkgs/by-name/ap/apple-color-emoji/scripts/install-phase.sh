# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
export XDG_CACHE_HOME="$TMPDIR/font-cache"
export FONTCONFIG_FILE=@fonts_conf@
test "$(fc-scan --format '%{postscriptname}' "$src")" = 'AppleColorEmoji'
install -Dm644 "$src" "$out/share/fonts/truetype/apple-color-emoji/font.ttf"
install -Dm444 @source_json@ "$out/share/doc/apple-color-emoji/manifest.json"
install -Dm444 @readme@ "$out/share/doc/apple-color-emoji/PACKAGING.md"
@repairArtworkCommand@
echo '@artworkVariant@' \
  >"$out/share/doc/apple-color-emoji/variant.txt"
runHook postInstall
