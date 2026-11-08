# shellcheck shell=bash
# The optional inherited loader path is read only when it is set.
export LD_LIBRARY_PATH="@vulkanLibraryPath@${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export VK_DRIVER_FILES="@driverManifest@"
