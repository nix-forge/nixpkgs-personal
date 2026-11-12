# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
export XDG_CACHE_HOME="$TMPDIR/font-cache"
mkdir -p "$XDG_CACHE_HOME/fontconfig"
export FONTCONFIG_FILE="$TMPDIR/fonts.conf"
cat >"$FONTCONFIG_FILE" <<EOF
<fontconfig><cachedir>$XDG_CACHE_HOME/fontconfig</cachedir></fontconfig>
EOF
font="$out/share/fonts/opentype/emojione-svg.otf"
cmp "$src" "$font"
test "$(fc-scan --format '%{family}' "$font")" = 'EmojiOne'
@assetsCheck@ "$font"
runHook postInstallCheck
