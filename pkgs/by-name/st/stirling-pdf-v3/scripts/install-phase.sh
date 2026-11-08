# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
mkdir -p "$out/share/stirling-pdf"
cp "$src" "$out/share/stirling-pdf/Stirling-PDF-with-login.jar"
cp -R "$scripts/scripts" "$out/share/stirling-pdf/scripts"
install -Dm644 "$scripts/LICENSE" "$out/share/licenses/stirling-pdf/LICENSE"
install -Dm644 "$scripts/app/proprietary/LICENSE" \
  "$out/share/licenses/stirling-pdf/app-proprietary-LICENSE"
install -Dm644 "$scripts/frontend/src/editor/proprietary/LICENSE" \
  "$out/share/licenses/stirling-pdf/frontend-proprietary-LICENSE"
makeWrapper @java@ "$out/bin/Stirling-PDF" \
  --add-flags "-jar $out/share/stirling-pdf/Stirling-PDF-with-login.jar" \
  --prefix PATH : @pythonPath@
runHook postInstall
