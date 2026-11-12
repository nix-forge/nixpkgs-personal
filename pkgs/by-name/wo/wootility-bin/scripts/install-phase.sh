# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

test -x Wootility.app/Contents/MacOS/Wootility
install -d "$out/Applications" "$out/bin"
cp -a Wootility.app "$out/Applications/"
ln -s "$out/Applications/Wootility.app/Contents/MacOS/Wootility" "$out/bin/wootility"

runHook postInstall
