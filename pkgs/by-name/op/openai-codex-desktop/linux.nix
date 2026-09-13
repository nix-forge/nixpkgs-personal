{
  lib,
  stdenv,
  stdenvNoCC,
  commonAttrs,
  dpkg,
  asar,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  writeShellApplication,
  util-linux,
  coreutils,
  bubblewrap,
  git,
  xdg-utils,
  alsa-lib,
  at-spi2-atk,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libglvnd,
  libnotify,
  libpulseaudio,
  libsecret,
  libusb1,
  libxkbcommon,
  nspr,
  nss,
  pango,
  pipewire,
  systemd,
  libX11,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libxcb,
  extraPackages ? [ ],
  pname,
}:
let
  browserPluginRelativePath = "lib/chatgpt/resources/plugins/openai-bundled/plugins/browser";

  prepareBundledBrowser = writeShellApplication {
    name = "openai-codex-desktop-prepare-bundled-browser";
    runtimeInputs = [
      coreutils
      util-linux
    ];
    text = ''
      if [ "$#" -ne 2 ]; then
        echo "usage: $0 BROWSER_PLUGIN_DIRECTORY APP_VERSION" >&2
        exit 2
      fi

      browser_plugin_source=$1
      app_version=$2
      case "$app_version" in
        "" | *[!A-Za-z0-9._-]*)
          echo "error: invalid Codex Desktop version: $app_version" >&2
          exit 2
          ;;
      esac

      browser_service_relative_path=scripts/browser-service.mjs
      browser_client_relative_path=scripts/browser-client.mjs
      browser_manifest_relative_path=.codex-plugin/plugin.json

      browser_plugin_is_complete() {
        candidate=$1
        [ ! -L "$candidate" ] \
          && [ -f "$candidate/$browser_service_relative_path" ] \
          && [ ! -L "$candidate/$browser_service_relative_path" ] \
          && [ -f "$candidate/$browser_client_relative_path" ] \
          && [ ! -L "$candidate/$browser_client_relative_path" ] \
          && [ -f "$candidate/$browser_manifest_relative_path" ] \
          && [ ! -L "$candidate/$browser_manifest_relative_path" ]
      }

      if ! browser_plugin_is_complete "$browser_plugin_source"; then
        echo "error: Codex Desktop $app_version does not contain a complete bundled browser plugin" >&2
        exit 1
      fi

      if [ -n "''${CODEX_HOME:-}" ]; then
        codex_state_root=$CODEX_HOME
      else
        codex_state_root="''${XDG_CONFIG_HOME:-$HOME/.config}/codex"
      fi
      browser_cache_parent="$codex_state_root/plugins/cache/openai-bundled/browser"
      browser_cache="$browser_cache_parent/$app_version"

      if browser_plugin_is_complete "$browser_cache"; then
        exit 0
      fi

      umask 077
      mkdir -p "$browser_cache_parent"
      exec 9>"$browser_cache_parent/.browser-$app_version.lock"
      flock 9

      # Another launcher may have completed the copy while this one waited.
      if browser_plugin_is_complete "$browser_cache"; then
        exit 0
      fi

      browser_cache_staging=$(mktemp -d "$browser_cache_parent/.browser-$app_version.XXXXXX")
      browser_cache_backup=

      cleanup_browser_cache() {
        if [ -n "$browser_cache_staging" ] && [ -e "$browser_cache_staging" ]; then
          rm -rf -- "$browser_cache_staging"
        fi
        if [ -n "$browser_cache_backup" ] && [ -e "$browser_cache_backup" ] && [ ! -e "$browser_cache" ]; then
          mv -T -- "$browser_cache_backup" "$browser_cache"
        fi
      }
      trap cleanup_browser_cache EXIT
      trap 'exit 1' HUP INT TERM

      cp -a -- "$browser_plugin_source/." "$browser_cache_staging/"
      chmod -R u+w -- "$browser_cache_staging"
      if ! browser_plugin_is_complete "$browser_cache_staging"; then
        echo "error: failed to stage the Codex Desktop $app_version browser plugin" >&2
        exit 1
      fi

      if [ -e "$browser_cache" ] || [ -L "$browser_cache" ]; then
        browser_cache_backup="$browser_cache_parent/.browser-$app_version.invalid.$$"
        mv -T -- "$browser_cache" "$browser_cache_backup"
      fi
      mv -T -- "$browser_cache_staging" "$browser_cache"
      browser_cache_staging=
      if [ -n "$browser_cache_backup" ]; then
        rm -rf -- "$browser_cache_backup"
        browser_cache_backup=
      fi

      trap - EXIT HUP INT TERM
    '';
  };

  launcher = writeShellApplication {
    name = "chatgpt";
    text = ''
      package_root=$(${lib.getExe' coreutils "dirname"} \
        "$(${lib.getExe' coreutils "dirname"} \
          "$(${lib.getExe' coreutils "readlink"} -f "''${BASH_SOURCE[0]}")")")
      "$package_root/libexec/prepare-bundled-browser" \
        "$package_root/${browserPluginRelativePath}" \
        "${commonAttrs.version}"
      exec -a "$0" "$package_root/libexec/chatgpt-wrapped" "$@"
    '';
  };
in
stdenvNoCC.mkDerivation (
  commonAttrs
  // {
    nativeBuildInputs = [
      asar
      autoPatchelfHook
      dpkg
      makeWrapper
      wrapGAppsHook3
    ];

    buildInputs = [
      alsa-lib
      at-spi2-atk
      atk
      cairo
      cups
      dbus
      expat
      gdk-pixbuf
      glib
      gtk3
      libdrm
      libgbm
      libusb1
      libxkbcommon
      nspr
      nss
      pango
      stdenv.cc.cc.lib
      systemd
      libX11
      libXcomposite
      libXdamage
      libXext
      libXfixes
      libXrandr
      libxcb
    ];

    # Electron loads these at runtime for notifications, credentials, audio,
    # GPU acceleration, and Wayland screen sharing.
    runtimeDependencies = [
      libglvnd
      libnotify
      libpulseaudio
      libsecret
      pipewire
      systemd
    ];

    strictDeps = true;
    __structuredAttrs = true;
    dontConfigure = true;
    dontBuild = true;
    # Preserve the upstream native payload, which contains helper binaries for
    # several architectures. GNU strip can corrupt or hang on foreign objects.
    dontStrip = true;
    dontWrapGApps = true;

    unpackPhase = ''
      runHook preUnpack

      mkdir source
      dpkg-deb -x "$src" source
      cd source

      runHook postUnpack
    '';

    patchPhase = ''
      runHook prePatch

      # detect-libc otherwise probes /usr/bin/ldd, then falls back to
      # process.report.getReport(), which traps in Electron 42 on NixOS when
      # @parcel/watcher initializes for a project.
      asar extract usr/lib/chatgpt/resources/app.asar app-asar
      substituteInPlace \
        app-asar/node_modules/@parcel/watcher/node_modules/detect-libc/lib/filesystem.js \
        --replace-fail \
        "const LDD_PATH = '/usr/bin/ldd';" \
        "const LDD_PATH = '${stdenv.cc.libc.bin}/bin/ldd';"
      sed -i '1i// Modified by nixpkgs-personal: use the Nix glibc ldd path.' \
        app-asar/node_modules/@parcel/watcher/node_modules/detect-libc/lib/filesystem.js
      # Keep native modules and their helper executables outside the archive
      # so autoPatchelf updates the files Electron actually loads.
      asar pack app-asar usr/lib/chatgpt/resources/app.asar --unpack-dir node_modules

      runHook postPatch
    '';

    installPhase = ''
      runHook preInstall

      install -d "$out/lib" "$out/libexec" "$out/bin" "$out/share/applications" "$out/share/pixmaps"
      cp -a usr/lib/chatgpt "$out/lib/"
      test -f "$out/${browserPluginRelativePath}/scripts/browser-service.mjs"
      # Scan workers can launch the bundled CLI directly. Use its system PATH
      # lookup: codex-resources/bwrap is reserved for an upstream hash-pinned
      # executable and cannot contain Nixpkgs' patched bubblewrap.
      wrapProgram "$out/lib/chatgpt/resources/codex" \
        --suffix PATH : ${lib.makeBinPath ([ bubblewrap ] ++ extraPackages)}
      install -m644 usr/share/applications/chatgpt.desktop \
        "$out/share/applications/chatgpt.desktop"
      install -m644 usr/share/pixmaps/chatgpt.png "$out/share/pixmaps/chatgpt.png"

      # Optional task tools stay separate from required application helpers.
      # No outer FHS/namespace wrapper: retain the host's development setup.
      makeShellWrapper "$out/lib/chatgpt/ChatGPT" "$out/libexec/chatgpt-wrapped" \
        --inherit-argv0 \
        --suffix PATH : ${
          lib.makeBinPath (
            [
              bubblewrap
              coreutils
              git
              xdg-utils
            ]
            ++ extraPackages
          )
        } \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland --enable-features=WaylandWindowDecorations,WebRTCPipeWireCapturer --enable-wayland-ime=true}}"
      install -m755 ${lib.getExe prepareBundledBrowser} "$out/libexec/prepare-bundled-browser"
      install -m755 ${lib.getExe launcher} "$out/bin/chatgpt"
      ln -s chatgpt "$out/bin/${pname}"

      runHook postInstall
    '';

    # These optional Qt shims attach to applications that already loaded Qt.
    # Giving them a package-specific Qt RPATH can mix incompatible Qt builds.
    # The Android and musl libraries belong to bundled prebuilds that cannot be
    # loaded by this glibc package, but keeping them preserves the app payload.
    autoPatchelfIgnoreMissingDeps = [
      "libQt5Core.so.5"
      "libQt5Gui.so.5"
      "libQt5Widgets.so.5"
      "libQt6Core.so.6"
      "libQt6Gui.so.6"
      "libQt6Widgets.so.6"
      "libc++_shared.so"
      "libc.musl-*.so.*"
      "liblog.so"
    ];

    postFixup = ''
      wrapGApp "$out/libexec/chatgpt-wrapped"
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck

      browser_plugin="$out/${browserPluginRelativePath}"
      browser_service="scripts/browser-service.mjs"
      check_root="$TMPDIR/openai-codex-desktop-browser-check"
      check_home="$check_root/codex"
      check_xdg_home="$check_root/xdg"
      current_cache="$check_home/plugins/cache/openai-bundled/browser/${commonAttrs.version}"
      xdg_cache="$check_xdg_home/codex/plugins/cache/openai-bundled/browser/${commonAttrs.version}"
      old_cache="$check_home/plugins/cache/openai-bundled/browser/previous-version"

      test -x "$out/bin/chatgpt"
      test -x "$out/libexec/chatgpt-wrapped"
      test -x "$out/libexec/prepare-bundled-browser"
      test -f "$browser_plugin/$browser_service"

      rm -rf "$check_root"
      mkdir -p "$old_cache"
      touch "$old_cache/keep"
      CODEX_HOME="$check_home" "$out/libexec/prepare-bundled-browser" \
        "$browser_plugin" "${commonAttrs.version}"
      test -f "$current_cache/$browser_service"
      test ! -L "$current_cache"
      test -w "$current_cache/$browser_service"
      test -f "$old_cache/keep"

      rm -rf "$current_cache"
      CODEX_HOME="$check_home" "$out/libexec/prepare-bundled-browser" \
        "$browser_plugin" "${commonAttrs.version}" &
      first_prepare_pid=$!
      CODEX_HOME="$check_home" "$out/libexec/prepare-bundled-browser" \
        "$browser_plugin" "${commonAttrs.version}" &
      second_prepare_pid=$!
      wait "$first_prepare_pid"
      wait "$second_prepare_pid"
      test -f "$current_cache/$browser_service"
      test ! -L "$current_cache"
      test -f "$old_cache/keep"

      env -u CODEX_HOME XDG_CONFIG_HOME="$check_xdg_home" \
        "$out/libexec/prepare-bundled-browser" "$browser_plugin" "${commonAttrs.version}"
      test -f "$xdg_cache/$browser_service"
      test ! -L "$xdg_cache"

      rm "$current_cache/$browser_service"
      CODEX_HOME="$check_home" "$out/libexec/prepare-bundled-browser" \
        "$browser_plugin" "${commonAttrs.version}"
      test -f "$current_cache/$browser_service"
      test -f "$old_cache/keep"
      test -z "$(find "$check_home/plugins/cache/openai-bundled/browser" -maxdepth 1 -name '.browser-*.invalid.*' -print -quit)"

      runHook postInstallCheck
    '';
  }
)
