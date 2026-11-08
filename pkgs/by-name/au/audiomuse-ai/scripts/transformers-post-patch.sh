# shellcheck shell=bash
substituteInPlace setup.py \
  --replace-fail '@upstream_upstreamTokenizersRequirement@' '@upstream_tokenizersRequirement@'
python setup.py deps_table_update
grep -Fq '"tokenizers": "@upstream_tokenizersRequirement@",' \
  src/transformers/dependency_versions_table.py
