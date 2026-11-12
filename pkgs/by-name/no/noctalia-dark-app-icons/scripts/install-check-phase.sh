# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
icons="$out/share/icons/@iconThemeName@"
gtk-update-icon-cache --validate "$icons"
cmp "$icons/scalable/apps/code.svg" "$icons/scalable/apps/visual-studio-code.svg"
cmp "$icons/scalable/apps/vscode.svg" "$icons/scalable/apps/visual-studio-code.svg"
for icon in chatgpt zen-browser vscode; do
  for size in 16 24 32 42 84; do
    rsvg-convert --width "$size" --height "$size" \
      --output "$TMPDIR/$icon-$size.png" "$icons/scalable/apps/$icon.svg"
  done
done
for icon in zoom sunshine; do
  for size in 16 24 32; do
    rsvg-convert --width "$size" --height "$size" \
      --output "$TMPDIR/$icon-symbolic-$size.png" "$icons/scalable/status/$icon-symbolic.svg"
  done
done
@assetsCheck@ "$TMPDIR" "$icons"
runHook postInstallCheck
