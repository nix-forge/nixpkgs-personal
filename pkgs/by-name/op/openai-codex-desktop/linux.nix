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

      install -d "$out/lib" "$out/bin" "$out/share/applications" "$out/share/pixmaps"
      cp -a usr/lib/chatgpt "$out/lib/"
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
      makeShellWrapper "$out/lib/chatgpt/ChatGPT" "$out/bin/chatgpt" \
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
      wrapGApp "$out/bin/chatgpt"
    '';
  }
)
