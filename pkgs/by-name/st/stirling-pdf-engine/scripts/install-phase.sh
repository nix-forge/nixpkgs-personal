# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
mkdir -p "$out/share/stirling-pdf-engine"
cp -R src .env "$out/share/stirling-pdf-engine/"
install -Dm644 LICENSE "$out/share/licenses/stirling-pdf-engine/LICENSE"
makeWrapper @python@/bin/python "$out/bin/stirling-pdf-engine" \
  --prefix PYTHONPATH : "$out/share/stirling-pdf-engine/src" \
  --add-flags '-m uvicorn stirling.api.app:app'
runHook postInstall
