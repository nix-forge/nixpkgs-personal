# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

app="$out/Applications/OCR Capture.app"
contents="$app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources" "$out/bin" "$out/share/doc/ocr-capture"
install -Dm755 build/hm-ocr-capture "$contents/MacOS/hm-ocr-capture"
install -Dm644 @infoPlist@ "$contents/Info.plist"
install -Dm644 README.md "$out/share/doc/ocr-capture/README.md"
install -Dm644 LICENSE "$out/share/doc/ocr-capture/LICENSE"
printf 'APPL????' >"$contents/PkgInfo"
ln -s "../Applications/OCR Capture.app/Contents/MacOS/hm-ocr-capture" "$out/bin/hm-ocr-capture"

runHook postInstall
