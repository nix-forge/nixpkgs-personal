#!/usr/bin/env bash
set -euo pipefail

cd "$1"
preload="$2"
cp steamwebhelper unrelated-cef-helper
export STEAM_SCALE_TEST_LOG="$PWD/events.log"
unset STEAM_SCALE_FACTOR STEAM_SCALE_TEST_INIT_FAIL

assert_log() {
  local expected="$1" actual
  actual="$(tr '\n' '|' <"$STEAM_SCALE_TEST_LOG")"
  if [[ $actual != "$expected" ]]; then
    echo "expected event log '$expected', got '$actual'" >&2
    return 1
  fi
}

run_helper() {
  local expected_status="$1" actual_status=0
  shift
  : >"$STEAM_SCALE_TEST_LOG"
  LD_PRELOAD="$preload" "$@" 2>diagnostics.log || actual_status=$?
  if [[ $actual_status != "$expected_status" ]]; then
    cat diagnostics.log >&2
    echo "expected exit $expected_status, got $actual_status" >&2
    return 1
  fi
}

for scale in 0.25 1.5 8.0; do
  STEAM_SCALE_FACTOR="$scale" run_helper 0 ./steamwebhelper
  printf -v expected 'initialize|scale=%.2f|' "$scale"
  assert_log "$expected"
done

STEAM_SCALE_FACTOR=1.5 run_helper 0 ./unrelated-cef-helper
assert_log 'initialize|'

# Absent and empty values silently leave the CEF default unchanged.
run_helper 0 ./steamwebhelper
assert_log 'initialize|'
test ! -s diagnostics.log
STEAM_SCALE_FACTOR='' run_helper 0 ./steamwebhelper
assert_log 'initialize|'
test ! -s diagnostics.log

for scale in '1.5trailing' '1.5 ' ' ' nan NaN inf -inf 0 -1 0.249 8.001 1e999 1e-999; do
  STEAM_SCALE_FACTOR="$scale" run_helper 0 ./steamwebhelper
  assert_log 'initialize|'
  grep -Fq 'ignoring invalid STEAM_SCALE_FACTOR' diagnostics.log
done

# Require CEF's exact failure status, so a sanitizer failure cannot pass here.
STEAM_SCALE_TEST_INIT_FAIL=1 STEAM_SCALE_FACTOR=1.5 run_helper 1 ./steamwebhelper
assert_log 'initialize|'
test ! -s diagnostics.log
