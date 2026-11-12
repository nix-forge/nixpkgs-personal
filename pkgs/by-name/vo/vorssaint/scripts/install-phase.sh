# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

app="$out/Applications/PersonalMonitor.app"
contents="$app/Contents"
resources="$contents/Resources"
helperID="io.github.ianhollow.personalmonitor.fan-control"

mkdir -p "$contents"/{MacOS,Resources,Frameworks,Library/LaunchDaemons,Library/LaunchServices}
install -Dm755 "$buildDir/PersonalMonitor" "$contents/MacOS/PersonalMonitor"
install -Dm755 "$buildDir/$helperID" "$contents/Library/LaunchServices/$helperID"
install -Dm644 Resources/com.vorssaint.utils.fan-control.plist \
  "$contents/Library/LaunchDaemons/$helperID.plist"
install -Dm644 Resources/Info.plist "$contents/Info.plist"
install -Dm755 "$buildDir/libPersonalMonitorNowPlaying.dylib" "$contents/Frameworks/libPersonalMonitorNowPlaying.dylib"
install -Dm644 Resources/now-playing.pl "$resources/now-playing.pl"
install -Dm644 CHANGELOG.md "$resources/CHANGELOG.md"
install -Dm644 LICENSE "$out/share/doc/@pname@/LICENSE"
install -Dm644 TRADEMARKS.md "$out/share/doc/@pname@/TRADEMARKS.md"
install -Dm644 @readme@ "$out/share/doc/@pname@/PACKAGING.md"
install -Dm644 "$buildDir/AppIcon.icns" "$resources/AppIcon.icns"
install -Dm644 "$buildDir/MenuBarIcon.png" "$resources/MenuBarIcon.png"
install -Dm644 "$buildDir/MenuBarIcon@2x.png" "$resources/MenuBarIcon@2x.png"
install -Dm644 "$buildDir/BrandMark.png" "$resources/BrandMark.png"
printf 'APPL????' >"$contents/PkgInfo"

cp -R Resources/*.lproj "$resources/"
cp -R Resources/Gifs Resources/Images "$resources/"

makeWrapper "$contents/MacOS/PersonalMonitor" "$out/bin/@pname@"

runHook postInstall
