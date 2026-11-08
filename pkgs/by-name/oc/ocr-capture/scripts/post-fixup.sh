# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
@rcodesign@ sign \
  --code-signature-flags runtime \
  "$out/Applications/OCR Capture.app"
