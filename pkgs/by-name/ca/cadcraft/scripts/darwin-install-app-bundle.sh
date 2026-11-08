# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
app="$out/Applications/CADCraft.app/Contents"
mkdir -p "$app/MacOS" "$app/Resources"
mv "$out/bin/cadcraft" "$app/MacOS/CADCraft"
ln -s "../Applications/CADCraft.app/Contents/MacOS/CADCraft" "$out/bin/cadcraft"
cp assets/app-icon/cadcraft.icns "$app/Resources/CADCraft.icns"
cp -r "$out/share/doc/cadcraft/licenses" "$app/Resources/Licenses"
substitute packaging/macos/Info.plist.in "$app/Info.plist" \
  --subst-var-by VERSION "@version@" \
  --subst-var-by SHORT_VERSION "@source_upstreamVersion@" \
  --subst-var-by BUILD_SHA "@source_rev@"
# The Nixpkgs SDK/toolchain can require a newer OS than upstream's baseline.
substituteInPlace "$app/Info.plist" \
  --replace-fail '<string>11.0</string>' '<string>@deploymentTargetFlags@</string>'
printf 'APPL????' >"$app/PkgInfo"
