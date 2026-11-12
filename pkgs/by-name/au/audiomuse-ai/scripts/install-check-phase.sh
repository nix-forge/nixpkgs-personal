# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck
export DATABASE_URL=
cd @appDir@ || exit
python -m compileall -q .
for program in "$out"/bin/audiomuse-ai-*; do
  head -n 1 "$program" | grep -q '/bin/bash'
done
python @pythonCheck1@
runHook postInstallCheck
