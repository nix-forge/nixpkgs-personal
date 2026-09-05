# steam-cef-scale-override

An opt-in `LD_PRELOAD` interposer for the Steam desktop client's CEF UI. It
calls Steam's exported `cef_set_force_device_scale_factor` immediately after a
successful `cef_initialize`, allowing Steam to render sharp text while a
Wayland compositor leaves XWayland buffers unscaled.

The library is deliberately inert unless all of these conditions hold:

- the executable basename is exactly `steamwebhelper`;
- `STEAM_SCALE_FACTOR` is present and is a finite number from `0.25` to `8.0`;
- CEF initialized successfully; and
- the Steam-provided scale function is available.

This is a temporary compatibility package, not an upstream Steam API. Remove
it when Valve's documented `STEAM_FORCE_DESKTOPUI_SCALING` or
`-forcedesktopscaling` path works again.

The implementation is derived from
[`steam-hidpi-shim`](https://github.com/katerinakosac51-creator/steam-hidpi-shim),
commit `f6651b1d6e85800885ea2b251ffc37c4e68df7e4`, under the included MIT
license. This version narrows process scope, removes the unnecessary
`cef_execute_process` hook and constructor, validates the complete scale
string, fails open, enables linker hardening, and adds behavioral tests.
