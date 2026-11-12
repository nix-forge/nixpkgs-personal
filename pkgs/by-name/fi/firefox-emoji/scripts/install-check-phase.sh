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
font="$out/share/fonts/truetype/FirefoxEmoji.ttf"
cmp "$src" "$font"
test "$(fc-scan --format '%{family}' "$font")" = 'Firefox Emoji'
@assetsCheck@ "$font"
runHook postInstallCheck
