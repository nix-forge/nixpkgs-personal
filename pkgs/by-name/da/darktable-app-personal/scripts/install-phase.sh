# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
app="$out/Applications/darktable.app"
install -d "$app/Contents/MacOS" "$app/Contents/Resources"
ln -s "@darktable@/bin/darktable" "$app/Contents/MacOS/darktable"
# Use this dependency's template and icon so associations follow upstream updates.
cp packaging/macosx/Icons.icns "$app/Contents/Resources/Icons.icns"
python3 @configureBundle@ packaging/macosx/Info.plist \
  "$app/Contents/Info.plist" @version@ @minimumMacOS@
test -L "$app/Contents/MacOS/darktable"
test -s "$app/Contents/Info.plist"
runHook postInstall
