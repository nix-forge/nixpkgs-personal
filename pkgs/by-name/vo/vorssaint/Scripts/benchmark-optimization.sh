#!/usr/bin/env bash
set -euo pipefail

# Run on unpacked source after patches and rebrand.py. Only the fixture-based
# fan helper selftest runs. The application and Now Playing adapter never run.
if [[ $# != 1 || ! -d $1/Sources/Vorssaint ]]; then
  printf 'usage: %s PATCHED_SOURCE_DIRECTORY\n' "$0" >&2
  exit 2
fi
cd -- "$1"
swiftc=${SWIFTC:-swiftc}
build_runs=${BENCHMARK_BUILD_RUNS:-3}
test_runs=${BENCHMARK_TEST_RUNS:-20}
for count in "$build_runs" "$test_runs"; do
  if [[ ! $count =~ ^[1-9][0-9]*$ ]]; then
    printf 'benchmark run counts must be positive integers\n' >&2
    exit 2
  fi
done
work=$(mktemp -d "${TMPDIR:-/tmp}/vorssaint-optimization.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
"$swiftc" --version
flags=(-swift-version 5 -target arm64-apple-macosx14.0)
helper_sources=(
  Sources/Vorssaint/Services/FanControl/FanControlSupport.swift
  Sources/Vorssaint/Services/FanControl/FanControlXPC.swift
  Sources/Vorssaint/Services/SystemMonitor/SMCClient.swift
  Sources/Vorssaint/Services/Metrics/TemperatureSensorSelector.swift
  Sources/Vorssaint/Services/FanControl/FanControlHardware.swift
  Sources/FanControlHelper/main.swift
)
app_sources=()
if [[ ${VORSSAINT_BENCHMARK_APP:-0} == 1 ]]; then
  while IFS= read -r source_file; do
    app_sources+=("$source_file")
  done < <(find Sources/Vorssaint -type f -name '*.swift' | LC_ALL=C sort)
fi
for ((run = 1; run <= build_runs; run++)); do
  for mode in baseline wmo; do
    optimization=(-O)
    if [[ $mode == wmo ]]; then optimization=(-O -whole-module-optimization); fi
    printf '\n%s helper build %d: wall/CPU time and peak RSS\n' "$mode" "$run"
    /usr/bin/time -l "$swiftc" "${flags[@]}" "${optimization[@]}" "${helper_sources[@]}" -o "$work/helper-$mode"
    printf '%s helper bytes: ' "$mode"
    wc -c <"$work/helper-$mode"
    "$work/helper-$mode" --selftest
    if [[ ${VORSSAINT_BENCHMARK_APP:-0} == 1 ]]; then
      printf '\n%s application build %d\n' "$mode" "$run"
      /usr/bin/time -l "$swiftc" "${flags[@]}" "${optimization[@]}" \
        -I Sources/VMStatisticsCompat -I Sources/HIDEventSystem "${app_sources[@]}" -o "$work/app-$mode"
      printf '%s application bytes: ' "$mode"
      wc -c <"$work/app-$mode"
    fi
  done
done
for mode in baseline wmo; do
  "$work/helper-$mode" --selftest >/dev/null
  for ((run = 1; run <= test_runs; run++)); do
    printf '\n%s fixture selftest %d\n' "$mode" "$run"
    /usr/bin/time -l "$work/helper-$mode" --selftest
  done
done
