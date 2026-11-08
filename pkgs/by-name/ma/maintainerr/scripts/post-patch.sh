# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
node @manifestProgram@ "$version"
test "$(find .yarn/releases -maxdepth 1 -name 'yarn-*.cjs' | wc -l)" -eq 1
substituteInPlace apps/server/src/app/config/typeOrmConfig.ts \
  --replace-fail "/opt/app/apps/server/dist/database/migrations" \
  "$out/libexec/maintainerr/apps/server/dist/database/migrations"
printf '%s\n' 'VITE_BASE_PATH=/__PATH_PREFIX__' >>apps/ui/.env
