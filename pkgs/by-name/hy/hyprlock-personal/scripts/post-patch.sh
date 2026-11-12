# shellcheck shell=bash
substituteInPlace CMakeLists.txt --replace-fail \
  'pkg_get_variable(WAYLAND_SCANNER_PKGDATA_DIR wayland-scanner pkgdatadir)' \
  'set(WAYLAND_SCANNER_PKGDATA_DIR "@waylandScanner@/share/wayland")'
