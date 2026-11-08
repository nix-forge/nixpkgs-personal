# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

app="$out/Applications/Spotify.app"
install -d "$app"
tar -xpf @spotifySource@ -C "$app"
chmod -R u+rwX "$app"

# Keep the upstream patcher offline and use Nix-provided tools rather than
# absolute host paths, which the Darwin sandbox does not expose.
fakeBin="$TMPDIR/fake-bin"
install -d "$fakeBin"
printf '%s\n' '#!/bin/sh' 'exit 1' >"$fakeBin/curl"
chmod +x "$fakeBin/curl"
cat >"$fakeBin/xattr" <<'EOF'
#!/bin/sh
if [ "$#" -eq 2 ] && [ "$1" = "-cr" ]; then
  exit 0
fi
printf 'unsupported xattr invocation: %s\n' "$*" >&2
exit 1
EOF
chmod +x "$fakeBin/xattr"

export HOME="$TMPDIR/spotx-home"
export PATH="$fakeBin:$PATH"
export SPOTX_BUILD_MODE=true
install -d "$HOME"

spotxScript="$TMPDIR/spotx.sh"
sed \
  -e 's|/usr/bin/xattr|xattr|g' \
  -e 's|/usr/bin/file|file|g' \
  -e 's|/usr/bin/tr|tr|g' \
  -e 's|"mach-o 64-bit executable arm64")|*"mach-o 64-bit"*"arm64"*)|' \
  -e 's|"mach-o 64-bit executable x86_64")|*"mach-o 64-bit"*"x86_64"*)|' \
  @spotxSource@/spotx.sh >"$spotxScript"

@bash@ "$spotxScript" \
  -F @sourceVersion@ \
  -P "$out/Applications" \
  --blockupdates \
  --skipcodesign \
  @patchArguments@

unzip -p "$app/Contents/Resources/Apps/xpui.spa" >"$TMPDIR/spotx-xpui-content"
grep -Fq '//# SpotX was here' "$TMPDIR/spotx-xpui-content"
rm -f "$app/Contents/MacOS/Spotify.bak"
rm -f "$app/Contents/Resources/Apps/xpui.bak"

runHook postInstall
runHook postInstallCheck
