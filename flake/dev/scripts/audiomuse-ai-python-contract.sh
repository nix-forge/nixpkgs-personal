# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
mkdir -p "$TMPDIR/audiomuse-ai"
cp -R @audiomuse_applicationSource@/. "$TMPDIR/audiomuse-ai/"
export AUDIOMUSE_SOURCE="$TMPDIR/audiomuse-ai"
export PYTHONPYCACHEPREFIX="$TMPDIR/pycache"
export DATABASE_URL=
mkdir -p "$PYTHONPYCACHEPREFIX"
python -m compileall -q "$AUDIOMUSE_SOURCE"
python @pkgs_replaceVars_scripts_packages_check_py_source_python_goo@
python @tokenizerCheck@
touch "$out"
