# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

export XDG_CACHE_HOME="$TMPDIR/font-cache"
export FONTCONFIG_FILE=@fonts_conf@
workdir="$TMPDIR/font-extraction"
isodir="$workdir/iso"
extracteddir="$workdir/extracted"
mkdir -p "$isodir" "$extracteddir"

7zz x -y -o"$isodir" "$src" 'sources/install.wim' >/dev/null

7zz e -y -o"$extracteddir" "$isodir/sources/install.wim" \
  'Windows/Fonts/*' \
  'Windows/System32/Licenses/neutral/*/*/license.rtf' >/dev/null

if [ ! -f "$extracteddir/license.rtf" ]; then
  echo "Missing license.rtf in install.wim extraction output" >&2
  exit 1
fi

mapfile -t fontPaths < <(
  find "$extracteddir" -maxdepth 1 -type f \
    \( -iname '*.ttf' -o -iname '*.ttc' \) \
    -print | LC_ALL=C sort -f
)
if [ "${#fontPaths[@]}" -eq 0 ]; then
  echo "No .ttf/.ttc font files were extracted from install.wim" >&2
  exit 1
fi

python3 @inspector@/font_manifest.py "$extracteddir" @manifest_json@

install -d "$out/share/fonts/truetype"
for fontPath in "${fontPaths[@]}"; do
  fontFile="$(basename "$fontPath")"
  install -m444 "$fontPath" "$out/share/fonts/truetype/$fontFile"
done

install -d "$out/share/licenses/@pname@"
install -m444 "$extracteddir/license.rtf" "$out/share/licenses/@pname@/license.rtf"

python3 @inspector@/font_manifest.py "$out/share/fonts/truetype" @manifest_json@
install -Dm444 @manifest_json@ "$out/share/doc/@pname@/manifest.json"
install -Dm444 @readme@ "$out/share/doc/@pname@/README.md"
rm -rf "$workdir"

runHook postInstall
