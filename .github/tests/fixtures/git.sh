#!/usr/bin/env bash
set -eu
if [[ $1 == diff && $TEST_CASE == diff-failure ]]; then
  exit 128
fi
exec "$REAL_GIT" "$@"
