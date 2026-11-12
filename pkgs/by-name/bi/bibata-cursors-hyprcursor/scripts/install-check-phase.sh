# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck

cmp readme.adoc "$out/share/doc/@pname@/readme.adoc"

test "$(find "$out/share/icons" -mindepth 1 -maxdepth 1 -type d -name 'Bibata-*' | wc -l)" -eq @toString_builtins_length_themes@

@checkThemes@

runHook postInstallCheck
