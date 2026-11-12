# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
cp -R @source@/. source
chmod -R u+w source
mkdocs build --config-file source/site/mkdocs.yml --site-dir "$out" --strict
test -s "$out/index.html"
test -s "$out/search/search_index.json"
