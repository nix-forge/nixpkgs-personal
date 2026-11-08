#!/usr/bin/env bash
set -eu
if [[ $1 == build ]]; then
  printf '%s\n' "$*" >>"$BUILD_LOG"
  exit 0
fi
exec "$REAL_NIX" "$@"
