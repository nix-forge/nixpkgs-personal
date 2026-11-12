# shellcheck shell=bash
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
  '@available(macOS 26.0, *) func probe() { var request = RecognizeDocumentsRequest(); request.textRecognitionOptions.maximumCandidateCount = 3; _ = request.supportedRecognitionLanguages }' |
  swiftc -target @stdenv_hostPlatform_darwinArch@-apple-macosx@minimumMacOS@ \
    -swift-version @swiftLanguageVersion@ -typecheck - >/dev/null 2>&1; then
  featureFlags+=(-D OCR_CAPTURE_HAS_DOCUMENT_RECOGNITION)
  printf 'OCR Capture: enabling macOS 26 structured document recognition\n'
else
  printf 'OCR Capture: macOS 26 document API unavailable; building the legacy backend\n'
fi
# WMO reduced executable size with both 5.10 and 6.3; see the native
# benchmark script and README for the measured scope.
swiftc \
  -target @stdenv_hostPlatform_darwinArch@-apple-macosx@minimumMacOS@ \
  -O \
  -whole-module-optimization \
  -swift-version @swiftLanguageVersion@ \
  -strict-concurrency=complete \
  -warnings-as-errors \
  -parse-as-library \
  -module-name OCRCapture \
  -framework AppKit \
  -framework CoreGraphics \
  -framework Foundation \
  -framework ImageIO \
  -framework Vision \
  "${featureFlags[@]}" \
  "${appSources[@]}" \
  -o build/hm-ocr-capture

runHook postBuild
