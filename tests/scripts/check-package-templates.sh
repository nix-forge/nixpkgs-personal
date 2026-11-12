# shellcheck shell=bash
# Nix supplies the output path through the build environment.
# shellcheck disable=SC2154
count=0
python_count=0
export PYTHONPYCACHEPREFIX="$TMPDIR/pycache"
while IFS= read -r path; do
  case $path in
  /nix/store/*.sh | /nix/store/*.sh.in)
    bash -n "$path"
    count=$((count + 1))
    ;;
  /nix/store/*.py)
    python3 -m py_compile "$path"
    python_count=$((python_count + 1))
    ;;
  esac
done < <(sort -u template-closure)
printf 'Validated %s Bash and %s Python package templates\n' "$count" "$python_count" >"$out"
