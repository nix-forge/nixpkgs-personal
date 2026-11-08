# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2034,SC2154
export HOME="$TMPDIR"
export SSL_CERT_FILE=@cacert@/etc/ssl/certs/ca-bundle.crt
export STIRLING_ENGINE_DATA_DIR="$TMPDIR/state"
export STIRLING_SMART_MODEL=test STIRLING_FAST_MODEL=test
export STIRLING_POSTHOG_ENABLED=false
@mainExecutable@ --host 127.0.0.1 --port 18084 >server.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
ready=0
for attempt in $(seq 1 60); do
  if curl --silent --fail http://127.0.0.1:18084/health >health.json; then
    ready=1
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
  sleep 1
done
if test "$ready" != 1; then
  cat server.log >&2
  exit 1
fi
test -s "$STIRLING_ENGINE_DATA_DIR/rag.db"
touch "$out"
