# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
test -f "$out/libexec/wardrowbe-frontend/server.js"
test -f "$out/libexec/wardrowbe-frontend/.next/BUILD_ID"
test -d "$out/libexec/wardrowbe-frontend/messages"
runHook postInstallCheck
