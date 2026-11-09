# shellcheck shell=bash
# Exercise the normal GPU canvas assertions with Mesa's CPU Vulkan adapter.
export LD_LIBRARY_PATH="@softwareRendererLibraryPath@${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export VK_DRIVER_FILES="@mesa@/share/vulkan/icd.d/lvp_icd.@vulkanIcdArchitecture@.json"
export LIBGL_ALWAYS_SOFTWARE=1
export LIBGL_DRIVERS_PATH="@mesa@/lib/dri"
export __EGL_VENDOR_LIBRARY_FILENAMES="@mesa@/share/glvnd/egl_vendor.d/50_mesa.json"
export XDG_RUNTIME_DIR="$TMPDIR/runtime"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
