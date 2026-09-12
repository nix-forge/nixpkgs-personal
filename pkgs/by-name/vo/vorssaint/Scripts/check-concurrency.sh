#!/usr/bin/env bash
set -euo pipefail

# Run on the unpacked source after package patches and rebrand.py have run.
# The app and helper have known upstream diagnostics. Keep this an explicit
# diagnostic lane until their actor migration is complete.
if [[ $# != 1 || ! -d $1/Sources/Vorssaint ]]; then
  printf 'usage: %s PATCHED_SOURCE_DIRECTORY\n' "$0" >&2
  exit 2
fi
cd -- "$1"
swiftc=${SWIFTC:-swiftc}
flags=(-typecheck -swift-version 5 -strict-concurrency=complete -target arm64-apple-macosx14.0)
if [[ ${VORSSAINT_WARNINGS_AS_ERRORS:-0} == 1 ]]; then
  flags+=(-warnings-as-errors)
fi
app_sources=()
while IFS= read -r source_file; do
  app_sources+=("$source_file")
done < <(find Sources/Vorssaint -type f -name '*.swift' | LC_ALL=C sort)

status=0
printf 'Checking application concurrency\n' >&2
"$swiftc" "${flags[@]}" -I Sources/VMStatisticsCompat -I Sources/HIDEventSystem \
  "${app_sources[@]}" || status=1
printf 'Checking fan helper concurrency\n' >&2
"$swiftc" "${flags[@]}" \
  Sources/Vorssaint/Services/FanControl/FanControlSupport.swift \
  Sources/Vorssaint/Services/FanControl/FanControlXPC.swift \
  Sources/Vorssaint/Services/SystemMonitor/SMCClient.swift \
  Sources/Vorssaint/Services/Metrics/TemperatureSensorSelector.swift \
  Sources/Vorssaint/Services/FanControl/FanControlHardware.swift \
  Sources/FanControlHelper/main.swift || status=1
printf 'Checking Now Playing adapter concurrency\n' >&2
"$swiftc" "${flags[@]}" -warnings-as-errors \
  Sources/NowPlayingAdapter/NowPlayingAdapter.swift || status=1
exit "$status"
