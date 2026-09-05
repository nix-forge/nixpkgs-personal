{
  coreutils,
  file,
  findutils,
  gnugrep,
  lib,
  rcodesign,
  re-plistbuddy,
  swiftPackages,
  writeText,
}:

let
  inherit (swiftPackages) stdenv swift;
  version = "0.1.0";
  minimumMacOS = "14.0";
  swiftLanguageVersion = if lib.versionAtLeast swift.version "6" then "6" else "5";
  infoPlist = writeText "OCRCapture-Info.plist" (
    lib.generators.toPlist { escape = true; } {
      CFBundleDevelopmentRegion = "en";
      CFBundleDisplayName = "OCR Capture";
      CFBundleExecutable = "hm-ocr-capture";
      CFBundleIdentifier = "dev.ianmh.OCRCapture";
      CFBundleInfoDictionaryVersion = "6.0";
      CFBundleName = "OCR Capture";
      CFBundlePackageType = "APPL";
      CFBundleShortVersionString = version;
      CFBundleSupportedPlatforms = [ "MacOSX" ];
      CFBundleVersion = "1";
      LSApplicationCategoryType = "public.app-category.productivity";
      LSMinimumSystemVersion = minimumMacOS;
      LSMultipleInstancesProhibited = true;
      LSUIElement = true;
      NSHighResolutionCapable = true;
      NSScreenCaptureUsageDescription = "OCR Capture reads only the screen area you select and recognizes its text locally.";
      NSHumanReadableCopyright = "Copyright © 2026 Ian Holloway";
    }
  );
in
stdenv.mkDerivation {
  pname = "ocr-capture";
  inherit version;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Package.swift
      ./.periphery.yml
      ./.swift-format
      ./.swiftlint.yml
      ./LICENSE
      ./Scripts
      ./Sources
      ./Tests
      ./README.md
    ];
  };

  nativeBuildInputs = [
    coreutils
    file
    findutils
    gnugrep
    rcodesign
    re-plistbuddy
    swift
  ];
  strictDeps = true;
  MACOSX_DEPLOYMENT_TARGET = minimumMacOS;
  # The wrapper injects this exact host-architecture deployment target. Its
  # generic multi-target warning is therefore a false positive, not a cross
  # compilation warning.
  NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING = 1;

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    mkdir -p build
    appSources=()
    while IFS= read -r sourceFile; do
      appSources+=("$sourceFile")
    done < <(find Sources/OCRCapture -type f -name '*.swift' | LC_ALL=C sort)

    # The Swift compiler and Apple SDK move independently in nixpkgs. Probe the
    # actual Vision module instead of guessing from the compiler version, so a
    # Swift 6 update with an older SDK keeps building the legacy backend while a
    # macOS 26 SDK automatically enables the structured document backend.
    featureFlags=(-D OCR_CAPTURE_NIX_BUILD)
    if printf '%s\n' \
      'import Vision' \
      '@available(macOS 26.0, *) func probe() { var request = RecognizeDocumentsRequest(); request.textRecognitionOptions.maximumCandidateCount = 3; _ = request.supportedRecognitionLanguages }' \
      | swiftc -swift-version ${swiftLanguageVersion} -typecheck - >/dev/null 2>&1
    then
      featureFlags+=(-D OCR_CAPTURE_HAS_DOCUMENT_RECOGNITION)
      printf 'OCR Capture: enabling macOS 26 structured document recognition\n'
    else
      printf 'OCR Capture: macOS 26 document API unavailable; building the legacy backend\n'
    fi
    swiftc \
      -O \
      -swift-version ${swiftLanguageVersion} \
      -strict-concurrency=complete \
      -warnings-as-errors \
      -parse-as-library \
      -module-name OCRCapture \
      -framework AppKit \
      -framework CoreGraphics \
      -framework Foundation \
      -framework ImageIO \
      -framework Vision \
      "''${featureFlags[@]}" \
      "''${appSources[@]}" \
      -o build/hm-ocr-capture

    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    build/hm-ocr-capture selftest

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    app="$out/Applications/OCR Capture.app"
    contents="$app/Contents"
    mkdir -p "$contents/MacOS" "$contents/Resources" "$out/bin" "$out/share/doc/ocr-capture"
    install -Dm755 build/hm-ocr-capture "$contents/MacOS/hm-ocr-capture"
    install -Dm644 ${infoPlist} "$contents/Info.plist"
    install -Dm644 README.md "$out/share/doc/ocr-capture/README.md"
    install -Dm644 LICENSE "$out/share/doc/ocr-capture/LICENSE"
    printf 'APPL????' > "$contents/PkgInfo"
    ln -s "../Applications/OCR Capture.app/Contents/MacOS/hm-ocr-capture" "$out/bin/hm-ocr-capture"

    runHook postInstall
  '';

  postFixup = ''
    ${lib.getExe rcodesign} sign \
      --code-signature-flags runtime \
      "$out/Applications/OCR Capture.app"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    app="$out/Applications/OCR Capture.app"
    executable="$app/Contents/MacOS/hm-ocr-capture"
    info="$app/Contents/Info.plist"
    test -x "$executable"
    test -s "$app/Contents/_CodeSignature/CodeResources"
    test -L "$out/bin/hm-ocr-capture"
    plutil -lint "$info"
    test "$(plutil -extract CFBundleIdentifier raw -o - "$info")" = "dev.ianmh.OCRCapture"
    test "$(plutil -extract LSMinimumSystemVersion raw -o - "$info")" = "${minimumMacOS}"
    test "$(plutil -extract LSMultipleInstancesProhibited raw -o - "$info")" = "true"
    test "$(plutil -extract LSUIElement raw -o - "$info")" = "true"
    file "$executable" | grep -Fq 'Mach-O 64-bit arm64 executable'
    otool -l "$executable" | grep -A4 -F 'cmd LC_BUILD_VERSION' | grep -Fq 'minos ${minimumMacOS}'
    "$out/bin/hm-ocr-capture" help | grep -Fq 'hm-ocr-capture capture'

    while read -r dependency _; do
      case "$dependency" in
        /System/* | /usr/lib/*) ;;
        *)
          printf 'error: unexpected dynamic dependency: %s\n' "$dependency" >&2
          exit 1
          ;;
      esac
    done < <(otool -L "$executable" | tail -n +2)

    signatureInfo="$(${lib.getExe rcodesign} print-signature-info "$executable")"
    printf '%s\n' "$signatureInfo" | grep -Fq 'flags: CodeSignatureFlags(ADHOC | RUNTIME)'
    printf '%s\n' "$signatureInfo" | grep -Fq 'identifier: dev.ianmh.OCRCapture'

    runHook postInstallCheck
  '';

  meta = {
    description = "Native macOS region-screenshot OCR tool";
    homepage = "https://github.com/ianmh/nixpkgs-personal";
    license = lib.licenses.mit;
    mainProgram = "hm-ocr-capture";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };

  passthru = {
    inherit swiftLanguageVersion;
    swiftVersion = swift.version;
    documentRecognition = "compile-probed";
  };
}
