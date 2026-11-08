# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck

app="$out/Applications/OCR Capture.app"
executable="$app/Contents/MacOS/hm-ocr-capture"
info="$app/Contents/Info.plist"
test -x "$executable"
test -s "$app/Contents/_CodeSignature/CodeResources"
test -L "$out/bin/hm-ocr-capture"
plutil -lint "$info"
test "$(plutil -extract CFBundleIdentifier raw -o - "$info")" = "dev.ianmh.OCRCapture"
test "$(plutil -extract LSMinimumSystemVersion raw -o - "$info")" = "@minimumMacOS@"
test "$(plutil -extract LSMultipleInstancesProhibited raw -o - "$info")" = "true"
test "$(plutil -extract LSUIElement raw -o - "$info")" = "true"
file "$executable" | grep -Fq 'Mach-O 64-bit arm64 executable'
otool -l "$executable" | grep -A4 -F 'cmd LC_BUILD_VERSION' | grep -Fq 'minos @minimumMacOS@'
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

signatureInfo="$(@rcodesign@ print-signature-info "$executable")"
printf '%s\n' "$signatureInfo" | grep -Fq 'flags: CodeSignatureFlags(ADHOC | RUNTIME)'
printf '%s\n' "$signatureInfo" | grep -Fq 'identifier: dev.ianmh.OCRCapture'

runHook postInstallCheck
