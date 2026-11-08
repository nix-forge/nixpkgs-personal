# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
mkdir -p "$out"
cp dist/managed-login-renderer.cjs dist/mpv-message.cjs dist/managed-login.cjs dist/mpv-now-playing.cjs dist/mpv-readiness.cjs "$out/"
runHook postInstall
