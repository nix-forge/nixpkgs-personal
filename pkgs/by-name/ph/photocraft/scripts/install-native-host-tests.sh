# shellcheck shell=bash
# Nix provides builder variables and rendered artifact paths.
# shellcheck disable=SC2154
runHook preInstall
mkdir -p "$out/bin" "$out/libexec"
python3 @installer@ native-host-tests.json "$out/libexec/@hostName@-libtests" @targetName@
makeWrapper "$out/libexec/@hostName@-libtests" "$out/bin/@hostName@" --add-flags @testFlags@
runHook postInstall
