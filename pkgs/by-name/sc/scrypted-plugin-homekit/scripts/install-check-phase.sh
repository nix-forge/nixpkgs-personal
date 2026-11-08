# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
@python3@/bin/python3 @check_py@ \
  "$out/share/scrypted/plugins/@scrypted/homekit" @version@
runHook postInstallCheck
