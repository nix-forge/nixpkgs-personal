# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
fakeBin="$TMPDIR/spotx-fake-bin"
install -d "$fakeBin"
printf '%s\n' '#!/bin/sh' 'exit 1' >"$fakeBin/curl"
chmod +x "$fakeBin/curl"

export HOME="$TMPDIR/spotx-home"
export PATH="$fakeBin:$PATH"
export SPOTX_BUILD_MODE=true
mkdir -p "$HOME"

@bash@ @spotxSource@/spotx.sh \
  -P "$out/share/spotify" \
  @patchArguments@

unzip -p "$out/share/spotify/Apps/xpui.spa" >"$TMPDIR/spotx-xpui-content"
grep -Fq '//# SpotX was here' "$TMPDIR/spotx-xpui-content"
rm -f "$out/share/spotify/spotify.bak"
rm -f "$out/share/spotify/Apps/xpui.bak"
