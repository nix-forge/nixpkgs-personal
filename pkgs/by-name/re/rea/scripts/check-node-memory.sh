#!/usr/bin/env bash
set -euo pipefail

node=$1
source_archive=$2
tests=$(mktemp -d)
trap 'rm -rf -- "$tests"' EXIT
tar -xf "$source_archive" --strip-components=1 -C "$tests"
export JOBS="${NIX_BUILD_CORES:-3}"
"$node" --predictable-gc-schedule "$tests/test/parallel/test-memory-usage.js"
for attempt in 1 2 3; do
  echo "UPSTREAM_WORKER_MEMORY_ATTEMPT=$attempt"
  "$node" "$tests/test/parallel/test-worker-memory.js"
done
echo UPSTREAM_RSS_REGRESSION=PASS
