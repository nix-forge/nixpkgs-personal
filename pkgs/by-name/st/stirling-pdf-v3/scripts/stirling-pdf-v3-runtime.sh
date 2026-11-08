# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2034,SC2154
export HOME="$TMPDIR"
export SERVER_ADDRESS=127.0.0.1
export SERVER_PORT=18083
export SECURITY_ENABLELOGIN=true
export SECURITY_INITIALLOGIN_USERNAME=admin
export SECURITY_INITIALLOGIN_PASSWORD=test-only-password
export SYSTEM_ENABLEANALYTICS=false
export JAVA_TOOL_OPTIONS="-Xms128m -Xmx512m"
cd "$TMPDIR" || exit
@mainExecutable@ >server.log 2>&1 &
server_pid=$!
cleanup() {
  status=$?
  if test "$status" -ne 0; then
    tail -50 server.log >&2
    test ! -f status.json || cat status.json >&2
  fi
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT
set -E
trap 'echo "Stirling runtime check failed: $BASH_COMMAND" >&2' ERR
ready=0
for attempt in $(seq 1 90); do
  if curl --silent --fail http://127.0.0.1:18083/api/v1/info/status >status.json; then
    ready=1
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    break
  fi
  sleep 1
done
if test "$ready" -ne 1 || ! grep -q '"version":"@version@","status":"UP"' status.json; then
  tail -50 server.log >&2
  exit 1
fi
grep -q 'Admin user created: admin' server.log
! grep -q 'Default admin user created' server.log
test "$(curl --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:18083/)" = 200
# The 3.3 release removed its legacy CFF converter. Exercise the shipped font helper.
@fontHelperPython@ @package@/share/stirling-pdf/scripts/subset_cjk_fallback_fonts.py --help >font-helper-help.txt
test -f @package@/share/licenses/stirling-pdf/app-proprietary-LICENSE
curl --silent --fail http://127.0.0.1:18083/assets/vendor-embedpdf-DRTjIhXK.js >viewer.js
grep -q 'stirlingFamilyEntry' viewer.js
for font in LiberationSerif-Regular.ttf LiberationMono-Regular.ttf; do
  curl --silent --fail "http://127.0.0.1:18083/fonts/$font" >"$font"
  test -s "$font"
done
touch "$out"
