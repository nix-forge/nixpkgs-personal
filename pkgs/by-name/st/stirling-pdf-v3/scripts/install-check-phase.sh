# shellcheck shell=bash
# Nix supplies the installed output and temporary build directory.
# shellcheck disable=SC2154
runHook preInstallCheck
python3 @extract_viewer_py@ "$out/share/stirling-pdf/Stirling-PDF-with-login.jar" \
  BOOT-INF/classes/static/assets/vendor-embedpdf-DRTjIhXK.js "$TMPDIR/viewer-check.js"
node --check "$TMPDIR/viewer-check.js"
runHook postInstallCheck
node @check_viewer_font_fallback_mts@ "$TMPDIR/viewer-check.js"
