# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
@nodejs_24@/bin/node @nodeModulesCheck@ plugin-cjs "$out/lib/node_modules/homebridge-tsvesync"
@nodejs_24@/bin/node @credential_files_test_mts@ \
  "$out/lib/node_modules/homebridge-tsvesync/dist/utils/credential.js"
@nodejs_24@/bin/node @redirect_credentials_test_mts@ \
  "$out/lib/node_modules/homebridge-tsvesync"
runHook postInstallCheck
