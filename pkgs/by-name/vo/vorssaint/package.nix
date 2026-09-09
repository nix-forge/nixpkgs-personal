{
  lib,
  stdenv,
  fetchFromGitHub,
  coreutils,
  findutils,
  imagemagick,
  makeWrapper,
  python3,
  rcodesign,
  swift,
}:

let
  pname = "vorssaint";
  source = import ./source.nix;
  needsSwift510CompatibilityPatch = lib.versionOlder swift.version "6";
in
lib.warnIf (!needsSwift510CompatibilityPatch)
  ''
    vorssaint: Swift ${swift.version} is available; the Swift 5.10 compatibility
    patch was skipped. Verify the unpatched build, then remove
    swift-5.10-concurrency.patch and this version guard.
  ''
  (
    stdenv.mkDerivation (finalAttrs: {
      inherit pname;
      inherit (source) version;

      src = fetchFromGitHub source.src;

      # Nixpkgs currently ships Swift 5.10.1.  Do not carry this workaround into
      # Swift 6 silently: skipping it both validates the upstream source and
      # prompts removal of the now-dead patch via the warning above.
      patches = lib.optionals needsSwift510CompatibilityPatch [ ./swift-5.10-concurrency.patch ];
      postPatch = ''
        python3 ${./rebrand.py} .
      '';
      patchFlags = [
        "-p1"
        "--fuzz=0"
      ];

      nativeBuildInputs = [
        coreutils
        findutils
        imagemagick
        makeWrapper
        python3
        rcodesign
        swift
      ];
      strictDeps = true;

      dontConfigure = true;

      buildPhase = ''
        runHook preBuild

        buildDir="$PWD/build"
        mkdir -p "$buildDir"

        # Upstream deliberately builds with a plain swiftc invocation. Keep the
        # source discovery explicit and deterministic, while excluding no sources:
        # every file under Sources/Vorssaint belongs to the app target.
        appSources=()
        while IFS= read -r sourceFile; do
          appSources+=("$sourceFile")
        done < <(find Sources/Vorssaint -type f -name '*.swift' | sort)
        swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
          -I Sources/VMStatisticsCompat -I Sources/HIDEventSystem "''${appSources[@]}" \
          -o "$buildDir/PersonalMonitor"

        swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
          Sources/Vorssaint/Services/FanControl/FanControlSupport.swift \
          Sources/Vorssaint/Services/FanControl/FanControlXPC.swift \
          Sources/Vorssaint/Services/SystemMonitor/SMCClient.swift \
          Sources/Vorssaint/Services/Metrics/TemperatureSensorSelector.swift \
          Sources/Vorssaint/Services/FanControl/FanControlHardware.swift \
          Sources/FanControlHelper/main.swift \
          -o "$buildDir/io.github.ianhollow.personalmonitor.fan-control"
        "$buildDir/io.github.ianhollow.personalmonitor.fan-control" --selftest

        swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
          -emit-library -module-name PersonalMonitorNowPlaying \
          Sources/NowPlayingAdapter/NowPlayingAdapter.swift \
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
          icon_512x512@2x:1024
        do
          name="''${icon%%:*}"
          size="''${icon##*:}"
          magick ${./icon.svg} -trim -resize "$size"x"$size" \
            -gravity center -background '#f7f7f7' -extent "$size"x"$size" "$iconset/$name.png"
        done

        python - "$iconset" "$buildDir/AppIcon.icns" <<'PY'
        from pathlib import Path
        import struct
        import sys

        iconset = Path(sys.argv[1])
        entries = {
            "ic11": "icon_16x16@2x.png",
            "ic12": "icon_32x32@2x.png",
            "ic07": "icon_128x128.png",
            "ic13": "icon_128x128@2x.png",
            "ic08": "icon_256x256.png",
            "ic14": "icon_256x256@2x.png",
            "ic09": "icon_512x512.png",
            "ic10": "icon_512x512@2x.png",
        }
        payload = b"".join(
            kind.encode("ascii") + struct.pack(">I", len(data) + 8) + data
            for kind, filename in entries.items()
            for data in [(iconset / filename).read_bytes()]
        )
        Path(sys.argv[2]).write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
        PY

        magick ${./icon.svg} -trim -resize 26x20 -gravity center -background none -extent 26x20 \
          "$buildDir/MenuBarIcon.png"
        magick ${./icon.svg} -trim -resize 52x40 -gravity center -background none -extent 52x40 \
          "$buildDir/MenuBarIcon@2x.png"
        magick ${./icon.svg} -trim -resize 640x "$buildDir/BrandMark.png"

        runHook postBuild
      '';

      installPhase = ''
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
        install -Dm644 LICENSE "$out/share/doc/${pname}/LICENSE"
        install -Dm644 TRADEMARKS.md "$out/share/doc/${pname}/TRADEMARKS.md"
        install -Dm644 ${./README.md} "$out/share/doc/${pname}/PACKAGING.md"
        install -Dm644 "$buildDir/AppIcon.icns" "$resources/AppIcon.icns"
        install -Dm644 "$buildDir/MenuBarIcon.png" "$resources/MenuBarIcon.png"
        install -Dm644 "$buildDir/MenuBarIcon@2x.png" "$resources/MenuBarIcon@2x.png"
        install -Dm644 "$buildDir/BrandMark.png" "$resources/BrandMark.png"
        printf 'APPL????' > "$contents/PkgInfo"

        cp -R Resources/*.lproj "$resources/"
        cp -R Resources/Gifs Resources/Images "$resources/"

        makeWrapper "$contents/MacOS/PersonalMonitor" "$out/bin/${pname}"

        runHook postInstall
      '';

      # ServiceManagement requires the main app, its privileged helper and their
      # resources to be sealed as a single bundle. rcodesign provides a reproducible
      # ad-hoc signature; a public Nix derivation cannot embed a private Developer ID.
      postFixup = ''
        ${lib.getExe rcodesign} sign "$out/Applications/PersonalMonitor.app"
      '';

      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck

        python3 ${./check_bundle.py} "$out"

        "$out/Applications/PersonalMonitor.app/Contents/Library/LaunchServices/io.github.ianhollow.personalmonitor.fan-control" --selftest
        test -s "$out/Applications/PersonalMonitor.app/Contents/Frameworks/libPersonalMonitorNowPlaying.dylib"
        test -s "$out/Applications/PersonalMonitor.app/Contents/Resources/now-playing.pl"
        test -s "$out/Applications/PersonalMonitor.app/Contents/Resources/AppIcon.icns"
        test -s "$out/Applications/PersonalMonitor.app/Contents/Resources/MenuBarIcon.png"
        test -s "$out/Applications/PersonalMonitor.app/Contents/Resources/MenuBarIcon@2x.png"
        test -s "$out/Applications/PersonalMonitor.app/Contents/Resources/BrandMark.png"
        runHook postInstallCheck
      '';

      passthru = {
        appName = "PersonalMonitor";
        updateScript = [
          "python3"
          "pkgs/by-name/vo/vorssaint/update.py"
        ];
      };

      meta = {
        description = "PersonalMonitor, an unofficial build of the Vorssaint macOS toolkit";
        homepage = "https://vorssaint.com/";
        downloadPage = "https://github.com/vorssaint/vorssaint-utils/releases";
        changelog = "https://github.com/vorssaint/vorssaint-utils/releases/tag/v${finalAttrs.version}";
        license = lib.licenses.gpl3Plus;
        mainProgram = pname;
        platforms = [ "aarch64-darwin" ];
        sourceProvenance = [ lib.sourceTypes.fromSource ];
      };
    })
  )
