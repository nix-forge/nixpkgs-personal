#!/usr/bin/env bash
set -euo pipefail

# Keep completed derivations on this runner when an upstream fetch loses DNS or
# its connection. Compiler failures and hash mismatches remain immediate failures.
build_log=$(mktemp)
trap 'rm -f "$build_log"' EXIT
for attempt in 1 2 3; do
  if "$@" 2>&1 | tee "$build_log"; then
    exit 0
  else
    statuses=("${PIPESTATUS[@]}")
    result=${statuses[0]}
    if [[ $result == 0 ]]; then
      exit "${statuses[1]}"
    fi
  fi
  if [[ $attempt == 3 ]] ||
    ! grep -Fq 'error: cannot download source from any mirror' "$build_log" ||
    ! grep -Eq 'curl: \((6|7|18|28|35|52|56)\)' "$build_log"; then
    exit "$result"
  fi
  # --keep-going can report several dependency failures. A transient fetch in
  # that output must not hide a compiler error or a later permanent curl error.
  if grep -E 'curl: \([0-9]+\)' "$build_log" |
    grep -Ev 'curl: \((6|7|18|28|35|52|56)\)' >/dev/null ||
    grep -iE '(^|[^[:alpha:]])error([^[:alpha:]]|$)' "$build_log" |
    grep -ivE 'error: (cannot download source from any mirror|cannot build |[0-9]+ dependenc)' >/dev/null; then
    exit "$result"
  fi
  # Accept only current Nix diagnostics identifying source archive builders.
  # Other failed derivations must be dependency failures, never compiler failures.
  # Unknown formats stop conservatively instead of guessing what failed.
  if ! awk '
    /error: Cannot build / { failed = $0; waiting = 1 }
    /Reason:/ && waiting {
      if ($0 ~ /builder failed/) {
        if (failed !~ /-source[.]drv\047/) { invalid = 1; exit }
        source_failure = 1
      } else if ($0 !~ /dependenc.*failed/) {
        invalid = 1
        exit
      }
      waiting = 0
    }
    END { exit (invalid || waiting || !source_failure) }
  ' "$build_log"; then
    exit "$result"
  fi
  echo "::warning::Source fetch lost network access; retrying build ($attempt/2)."
  sleep "${FETCH_RETRY_DELAY_SECONDS:-15}"
done
