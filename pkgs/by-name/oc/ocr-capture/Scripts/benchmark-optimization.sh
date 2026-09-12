#!/usr/bin/env bash
set -euo pipefail

# Compare identical release sources with and without WMO. The selftest uses
# fixtures; it never captures a screen or writes to the clipboard.
package_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd -- "$package_root"
swiftc=${SWIFTC:-swiftc}
build_runs=${BENCHMARK_BUILD_RUNS:-3}
test_runs=${BENCHMARK_TEST_RUNS:-20}
for count in "$build_runs" "$test_runs"; do
  if [[ ! $count =~ ^[1-9][0-9]*$ ]]; then
    printf 'benchmark run counts must be positive integers\n' >&2
    exit 2
  fi
done
work=$(mktemp -d "${TMPDIR:-/tmp}/ocr-optimization.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
"$swiftc" --version
language=5
if "$swiftc" --version | grep -Eq 'Swift version ([6-9]|[1-9][0-9])\.'; then
  language=6
fi
flags=(-swift-version "$language" -strict-concurrency=complete -warnings-as-errors
  -parse-as-library -module-name OCRCapture -target arm64-apple-macosx14.0
  -D OCR_CAPTURE_NIX_BUILD)
if printf '%s\n' 'import Vision' \
  '@available(macOS 26.0, *) func probe() { var request = RecognizeDocumentsRequest(); request.textRecognitionOptions.maximumCandidateCount = 3; _ = request.supportedRecognitionLanguages }' |
  "$swiftc" -swift-version "$language" -typecheck - >/dev/null 2>&1; then
  flags+=(-D OCR_CAPTURE_HAS_DOCUMENT_RECOGNITION)
fi
sources=()
while IFS= read -r source_file; do
  sources+=("$source_file")
done < <(find Sources/OCRCapture -type f -name '*.swift' | LC_ALL=C sort)
for ((run = 1; run <= build_runs; run++)); do
  for mode in baseline wmo; do
    optimization=(-O)
    if [[ $mode == wmo ]]; then optimization=(-O -whole-module-optimization); fi
    printf '\n%s build %d: wall/CPU time and peak RSS\n' "$mode" "$run"
    /usr/bin/time -l "$swiftc" "${flags[@]}" "${optimization[@]}" "${sources[@]}" -o "$work/$mode"
    printf '%s bytes: ' "$mode"
    wc -c <"$work/$mode"
    "$work/$mode" selftest
  done
done
for mode in baseline wmo; do
  # One warmup, followed by process-startup plus fixture-selftest measurements.
  "$work/$mode" selftest >/dev/null
  for ((run = 1; run <= test_runs; run++)); do
    printf '\n%s fixture selftest %d\n' "$mode" "$run"
    /usr/bin/time -l "$work/$mode" selftest
  done
done
