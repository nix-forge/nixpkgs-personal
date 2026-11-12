# shellcheck shell=bash
runHook preCheck
$CXX -std=c++23 -Wall -Wextra -Werror -UNDEBUG -I../src \
  @test_bar_icon_policy_cpp@ -o bar-icon-policy-test
./bar-icon-policy-test
$CXX -std=c++23 -Wall -Wextra -Werror -UNDEBUG -I../src \
  @test_route_preference_cpp@ ../src/dbus/network/network_display.cpp \
  -o route-preference-test
./route-preference-test
meson introspect --tests >noctalia-tests.json
python3 @test_inventory_python@ noctalia-tests.json
meson test --no-rebuild --print-errorlogs -j "$NIX_BUILD_CORES"
cat >symbolic-widget-settings.toml <<'EOF'
[widget.active_window]
symbolic_icons = true

[widget.taskbar]
symbolic_icons = false

[widget.tray.icon_overrides]
example = "example-symbolic"
EOF
validation_output="$(./noctalia config validate symbolic-widget-settings.toml 2>&1)"
if grep -Fq 'unknown setting' <<<"$validation_output" ||
  ! grep -Fq 'Config is valid' <<<"$validation_output"; then
  printf '%s\n' "$validation_output" >&2
  exit 1
fi
runHook postCheck
