# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck

python3 @check_bundle_py@ "$out"
swift -module-cache-path "$buildDir/swift-modules/menu-icon-check" \
  @check_menu_bar_icon@ "$out/Applications/PersonalMonitor.app/Contents/Resources"

"$out/Applications/PersonalMonitor.app/Contents/Library/LaunchServices/io.github.ianhollow.personalmonitor.fan-control" --selftest
test -s "$out/Applications/PersonalMonitor.app/Contents/Frameworks/libPersonalMonitorNowPlaying.dylib"
test -s "$out/Applications/PersonalMonitor.app/Contents/Resources/now-playing.pl"
test -s "$out/Applications/PersonalMonitor.app/Contents/Resources/AppIcon.icns"
test -s "$out/Applications/PersonalMonitor.app/Contents/Resources/MenuBarIcon.png"
test -s "$out/Applications/PersonalMonitor.app/Contents/Resources/MenuBarIcon@2x.png"
test -s "$out/Applications/PersonalMonitor.app/Contents/Resources/BrandMark.png"
runHook postInstallCheck
