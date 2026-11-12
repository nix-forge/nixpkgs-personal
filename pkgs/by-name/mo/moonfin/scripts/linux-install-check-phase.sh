# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -x "$out/bin/moonfin"
test -s "$out/app/moonfin/lib/libapp.so"
test -s "$out/app/moonfin/lib/libflutter_linux_gtk.so"
test -s "$out/app/moonfin/lib/libpdfium.so"
test -s "$out/share/applications/org.moonfin.linux.desktop"
desktop-file-validate "$out/share/applications/org.moonfin.linux.desktop"
test -s "$out/share/icons/hicolor/512x512/apps/org.moonfin.linux.png"
runHook postInstallCheck
