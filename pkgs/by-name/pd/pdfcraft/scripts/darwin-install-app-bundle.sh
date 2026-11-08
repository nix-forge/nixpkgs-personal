# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
app="$out/Applications/PdfCraft.app/Contents"
mkdir -p "$app/MacOS" "$app/Resources"
mv "$out/bin/pdfcraft" "$app/MacOS/PdfCraft"
ln -s "../Applications/PdfCraft.app/Contents/MacOS/PdfCraft" "$out/bin/pdfcraft"
cp assets/app-icon/pdfcraft.icns "$app/Resources/PdfCraft.icns"
cp -r "$out/share/doc/pdfcraft/licenses" "$app/Resources/Licenses"
# Apple strict signature verification rejects external resource symlinks.
cp -RL @ocrModels@ "$app/Resources/models"
substitute packaging/macos/Info.plist.in "$app/Info.plist" \
  --subst-var-by VERSION "@version@" \
  --subst-var-by SHORT_VERSION "@source_upstreamVersion@" \
  --subst-var-by BUILD_SHA "@source_rev@"
# The Nixpkgs SDK/toolchain can require a newer OS than upstream's baseline.
substituteInPlace "$app/Info.plist" \
  --replace-fail '<string>11.0</string>' '<string>@deploymentTargetFlags@</string>'
printf 'APPL????' >"$app/PkgInfo"
