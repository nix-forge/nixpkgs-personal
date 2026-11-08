# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
app="$out/Applications/SoundCraft.app/Contents"
mkdir -p "$app/MacOS" "$app/Resources"
mv "$out/bin/soundcraft" "$app/MacOS/SoundCraft"
ln -s "../Applications/SoundCraft.app/Contents/MacOS/SoundCraft" "$out/bin/soundcraft"
cp assets/app-icon/soundcraft.icns "$app/Resources/SoundCraft.icns"
cp -r "$out/share/doc/soundcraft/licenses" "$app/Resources/Licenses"
substitute packaging/macos/Info.plist.in "$app/Info.plist" \
  --subst-var-by VERSION "@version@" \
  --subst-var-by SHORT_VERSION "@source_upstreamVersion@" \
  --subst-var-by BUILD_SHA "@source_rev@"
# The Nixpkgs SDK/toolchain can require a newer OS than upstream's baseline.
substituteInPlace "$app/Info.plist" \
  --replace-fail '<string>11.0</string>' '<string>@deploymentTargetFlags@</string>'
printf 'APPL????' >"$app/PkgInfo"
