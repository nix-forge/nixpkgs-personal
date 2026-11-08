# shellcheck shell=bash
# shellcheck disable=SC2154
# The runner-loader regression is independent of the compositor and rejects zero-test success.
mkdir -p runner
cp @runner@ runner/run_sway_clipboard.py
cp @runner_tests@ runner/test_sway_clipboard_runner.py
python3 runner/test_sway_clipboard_runner.py
dbus-run-session --config-file @dbus_session_configuration@ -- python3 runner/run_sway_clipboard.py \
  --sway @sway@ \
  --wl-copy @wl_copy@ \
  --wl-paste @wl_paste@ \
  --wayland-info @wayland_info@ \
  --test-executable @test_executable@ \
  --fixture @fixture@ \
  --evidence "$TMPDIR/evidence"
# Keep published check output concise. Detailed protocol captures stay in the build log/temp tree.
mkdir -p "$out"
cp "$TMPDIR/evidence/result.json" "$out/result.json"
