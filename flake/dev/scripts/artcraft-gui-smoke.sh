# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
export HOME="$TMPDIR/home"
export XDG_RUNTIME_DIR="$TMPDIR/runtime"
mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
unset WAYLAND_DISPLAY
# Interrupt stalled X11 round trips so Python releases its owned application.
# The supervisor supplies a hard bound if cleanup cannot finish.
xvfb-run -a -s '-screen 0 1280x800x24' timeout --signal=INT --kill-after=5s 35s env \
  LD_LIBRARY_PATH=@pkgs_lib_makeLibraryPath_packages_mesa@ \
  LIBGL_ALWAYS_SOFTWARE=1 \
  LIBGL_DRIVERS_PATH=@packages_mesa@/lib/dri \
  __EGL_VENDOR_LIBRARY_FILENAMES=@packages_mesa@/share/glvnd/egl_vendor.d/50_mesa.json \
  VK_DRIVER_FILES=@packages_mesa@/share/vulkan/icd.d/lvp_icd.@if_system_x86_64_linux_then_x86_64_else_aarch64@.json \
  bash @artcraft_gui_sh@ @pkgs_lib_escapeShellArg_packages_name_bin_name@
touch "$out"
