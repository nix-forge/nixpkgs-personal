#!/usr/bin/env bash
set -eu
if [[ $1 == build ]]; then
  printf '%s\n' "$*" >>"$BUILD_LOG"
  exit 0
fi
printf '%s\n' "$*" >>"$EVAL_LOG"
if [[ $* == *builtins.mapAttrs* && $* == *packages.x86_64-linux* ]]; then
  if [[ $TEST_CASE == malformed-current-map && $* != *git+file* ]] ||
    [[ $TEST_CASE == malformed-base-map && $* == *git+file* ]]; then
    printf '{"demo":"not-a-derivation"}\n'
    exit 0
  fi
fi
exec "$REAL_NIX" "$@"
