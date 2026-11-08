# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$out"
ln -s @fetchurl_source_ocr_detection@ "$out/text-detection.rten"
ln -s @fetchurl_source_ocr_recognition@ "$out/text-recognition.rten"
cp @fetchurl_source_ocr_license@ "$out/LICENSE-CC-BY-SA-4.0.txt"
