# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
install -Dm644 transfer_ownership.py "$out/libexec/soularr/transfer_ownership.py"
install -Dm644 soularr.py "$out/libexec/soularr/soularr.py"
makeWrapper @python@/bin/python "$out/bin/soularr" \
  --add-flags "$out/libexec/soularr/soularr.py"
runHook postInstall
