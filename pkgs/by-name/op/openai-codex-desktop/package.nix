{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  unzip,
  dpkg,
  asar,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  coreutils,
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
}:

let
  pname = "openai-codex-desktop";
  source = import ./source.nix;
  inherit (stdenv.hostPlatform) system;
  sourceForSystem =
    source.sources.${system} or (throw "${pname} does not provide an upstream artifact for ${system}");
  src = fetchurl {
    inherit (sourceForSystem) url hash;
    name = "${pname}-${sourceForSystem.version}-${system}.${
      if stdenv.hostPlatform.isDarwin then "zip" else "deb"
    }";
  };
  meta = {
    description = "OpenAI desktop app with ChatGPT, Work, and Codex";
    longDescription = ''
      OpenAI's unified desktop application. It includes ChatGPT, Work, and the
      Codex interface for local and cloud software-development tasks.
    '';
    homepage = "https://chatgpt.com/download/";
    downloadPage = "https://chatgpt.com/download/";
    changelog = "https://help.openai.com/en/articles/6825453-chatgpt-release-notes";
    license = lib.licenses.unfree;
    mainProgram = "chatgpt";
    platforms = builtins.attrNames source.sources;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
  passthru = {
    inherit (source) appName;
    inherit sourceForSystem;
    updateScript = [ ./update.py ];
  };
in
if stdenv.hostPlatform.isDarwin then
  stdenvNoCC.mkDerivation {
    inherit
      pname
      src
      meta
      passthru
      ;
    inherit (sourceForSystem) version;

    nativeBuildInputs = [ unzip ];
    sourceRoot = ".";
    strictDeps = true;
    __structuredAttrs = true;

    dontPatch = true;
    dontConfigure = true;
    dontBuild = true;
    # Generic fixup would invalidate OpenAI's notarized app bundle signature.
    dontFixup = true;

    installPhase = ''
      runHook preInstall

      install -d "$out/Applications" "$out/bin"
      cp -a "${source.appName}.app" "$out/Applications/"
      ln -s "$out/Applications/${source.appName}.app/Contents/MacOS/${source.appName}" \
        "$out/bin/chatgpt"
      ln -s chatgpt "$out/bin/${pname}"

      runHook postInstall
    '';
  }
else
  stdenvNoCC.mkDerivation {
    inherit
      pname
      src
      meta
      passthru
      ;
    inherit (sourceForSystem) version;

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
      # Keep native modules and their helper executables outside the archive
      # so autoPatchelf updates the files Electron actually loads.
      asar pack app-asar usr/lib/chatgpt/resources/app.asar --unpack-dir node_modules

      runHook postPatch
    '';

    installPhase = ''
      runHook preInstall

      install -d "$out/lib" "$out/bin" "$out/share/applications" "$out/share/pixmaps"
      cp -a usr/lib/chatgpt "$out/lib/"
      install -m644 usr/share/applications/chatgpt.desktop \
        "$out/share/applications/chatgpt.desktop"
      install -m644 usr/share/pixmaps/chatgpt.png "$out/share/pixmaps/chatgpt.png"

      makeShellWrapper "$out/lib/chatgpt/ChatGPT" "$out/bin/chatgpt" \
        --inherit-argv0 \
        --suffix PATH : ${
          lib.makeBinPath [
            coreutils
            git
            xdg-utils
          ]
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
