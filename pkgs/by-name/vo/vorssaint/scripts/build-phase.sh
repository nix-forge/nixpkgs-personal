# shellcheck shell=bash
runHook preBuild

buildDir="$PWD/build"
mkdir -p "$buildDir"
mkdir -p "$buildDir/swift-modules/sqlite" \
  "$buildDir/swift-modules/fan-helper" \
  "$buildDir/swift-modules/now-playing"
minimumMacOS=$(python3 @deploymentTarget@ Resources/Info.plist)
export MACOSX_DEPLOYMENT_TARGET="$minimumMacOS"

# Preserve the SDK module identity and supply only its omitted SQLite headers.
sqliteOverlay="$buildDir/sqlite-headers.json"
python3 @sqliteOverlay@ "$SDKROOT" "@sqliteHeaders@" "$sqliteOverlay"
# Framework, helper and adapter compilations own separate module caches.
sqliteFlags=(
  -module-cache-path "$buildDir/swift-modules/sqlite"
  -Xcc -ivfsoverlay -Xcc "$sqliteOverlay"
  -L "@sqliteLibraryPath@" -lsqlite3
  -Xlinker -rpath -Xlinker "@sqliteLibraryPath@"
)
swiftc -swift-version 5 -target "arm64-apple-macosx$minimumMacOS" \
  "${sqliteFlags[@]}" @sqliteCheck@ -o "$buildDir/check-sqlite"
"$buildDir/check-sqlite"

# Upstream deliberately builds with a plain swiftc invocation. Keep the
# source discovery explicit and deterministic, while excluding no sources:
# every file under Sources/Vorssaint belongs to the app target.
appSources=()
while IFS= read -r sourceFile; do
  appSources+=("$sourceFile")
done < <(find Sources/Vorssaint -type f -name '*.swift' | sort)
swiftc -O -swift-version 5 -target "arm64-apple-macosx$minimumMacOS" \
  -I Sources/VMStatisticsCompat -I Sources/HIDEventSystem \
  "${sqliteFlags[@]}" "${appSources[@]}" \
  -o "$buildDir/PersonalMonitor"

# Native 5.10 and 6.3 checks found a smaller helper with WMO.
swiftc -O -whole-module-optimization -swift-version 5 -target "arm64-apple-macosx$minimumMacOS" \
  -module-cache-path "$buildDir/swift-modules/fan-helper" \
  Sources/Vorssaint/Services/FanControl/FanControlSupport.swift \
  Sources/Vorssaint/Services/FanControl/FanControlXPC.swift \
  Sources/Vorssaint/Services/SystemMonitor/SMCClient.swift \
  Sources/Vorssaint/Services/Metrics/TemperatureSensorSelector.swift \
  Sources/Vorssaint/Services/FanControl/FanControlHardware.swift \
  Sources/FanControlHelper/main.swift \
  -o "$buildDir/io.github.ianhollow.personalmonitor.fan-control"
"$buildDir/io.github.ianhollow.personalmonitor.fan-control" --selftest

swiftc -O -swift-version 5 -target "arm64-apple-macosx$minimumMacOS" \
  -module-cache-path "$buildDir/swift-modules/now-playing" \
  -emit-library -module-name PersonalMonitorNowPlaying \
  Sources/NowPlayingAdapter/NowPlayingAdapter.swift \
  Sources/NowPlayingAdapter/NowPlayingQueue.swift \
  Sources/NowPlayingAdapter/NowPlayingSelection.swift \
  Sources/Vorssaint/Services/Notch/NotchPlaybackSource.swift \
  Sources/Vorssaint/Services/Notch/NotchPlaybackCommand.swift \
  -o "$buildDir/libPersonalMonitorNowPlaying.dylib"

# Generate independently drawn package artwork in the required sizes.
# The upstream name and artwork are reserved by TRADEMARKS.md.
iconset="$buildDir/AppIcon.iconset"
mkdir -p "$iconset"
for icon in \
  icon_16x16:16 \
  icon_16x16@2x:32 \
  icon_32x32:32 \
  icon_32x32@2x:64 \
  icon_128x128:128 \
  icon_128x128@2x:256 \
  icon_256x256:256 \
  icon_256x256@2x:512 \
  icon_512x512:512 \
  icon_512x512@2x:1024; do
  name="${icon%%:*}"
  size="${icon##*:}"
  magick @icon_svg@ -trim -resize "$size"x"$size" \
    -gravity center -background '#f7f7f7' -extent "$size"x"$size" "$iconset/$name.png"
done

python @pythonCheck1@ "$iconset" "$buildDir/AppIcon.icns"

# AppKit templates discard RGB, so never derive these from the opaque app tile.
magick -background none @menu_icon_svg@ -resize 26x20 \
  "$buildDir/MenuBarIcon.png"
magick -background none @menu_icon_svg@ -resize 52x40 \
  "$buildDir/MenuBarIcon@2x.png"
magick @icon_svg@ -trim -resize 640x "$buildDir/BrandMark.png"

runHook postBuild
