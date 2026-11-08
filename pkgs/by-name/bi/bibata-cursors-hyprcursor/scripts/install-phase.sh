# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

iconRoot="$out/share/icons"
mkdir -p "$iconRoot"
# Upstream records attribution and GPL-3.0-or-later in its AsciiDoc README.
install -Dm644 readme.adoc "$out/share/doc/@pname@/readme.adoc"
install -Dm644 @licenseText@ "$out/share/doc/@pname@/COPYING"

@installThemes@

runHook postInstall
