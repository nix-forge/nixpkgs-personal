# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
runHook preInstallCheck
export FONTCONFIG_FILE=@fonts_conf@
export XDG_CACHE_HOME="$TMPDIR/font-cache"
mkdir -p "$XDG_CACHE_HOME"
font="$out/share/fonts/truetype/MutantStandardEmoji.ttf"
family=$(fc-scan --format '%{family}' "$font" 2>"$TMPDIR/fc-scan.log")
# fc-scan can exit successfully after configuration errors.
if [ -s "$TMPDIR/fc-scan.log" ]; then
  cat "$TMPDIR/fc-scan.log" >&2
  exit 1
fi
test "$family" = 'Mutant Standard Emoji'
python @check_py@ "$font" @artwork@
runHook postInstallCheck
