{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  fetchurl,
  fetchzip,
  pnpmConfigHook,
  pnpm_11,
  nodejs_24,
  rustPlatform,
  cargo,
  rustc,
  pkg-config,
  libsecret,
  imagemagick,
  python3,
  unzip,
  _7zz,
  copyDesktopItems,
  makeDesktopItem,
  makeWrapper,
  autoPatchelfHook,
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
  commonAttrs,
  source,
}:
stdenv.mkDerivation (
  finalAttrs:
  commonAttrs
  // {
    src = fetchFromGitHub {
      owner = "pingdotgg";
      repo = "t3code";
      rev = source.linux.rev;
      hash = source.linux.hash;
    };

    # Offline mirror of the pnpm store. pnpmConfigHook installs from it with
    # --offline --ignore-scripts; lifecycle downloads (Electron, sharp) are
    # handled below instead of running vendor postinstall scripts.
    pnpmDeps = fetchPnpmDeps {
      pname = "${commonAttrs.pname}-pnpm-deps";
      inherit (finalAttrs) version src;
      pnpm = pnpm_11;
      fetcherVersion = 4;
      hash = source.linux.pnpmHash;
    };

    # Vendored crates for native/resource-monitor. cargoSetupHook points Cargo
    # at this copy and validates it against the source lockfile.
    cargoDeps = rustPlatform.fetchCargoVendor {
      pname = "${commonAttrs.pname}-cargo-deps";
      inherit (finalAttrs) version src;
      cargoRoot = "native/resource-monitor";
      hash = source.linux.cargoHash;
    };
    cargoRoot = "native/resource-monitor";

    # Fixed-output mirrors, exposed so update.py can refresh their hashes by
    # building these attributes directly.
    passthru = commonAttrs.passthru // {
      inherit (finalAttrs)
        pnpmDeps
        cargoDeps
        electronDistZip
        electronShasums
        ;
    };

    # pnpm 11 downloads the packageManager-pinned pnpm whenever the running
    # version differs, which fails inside the sandbox. The staged workspace
    # generated below inherits this pin and has no lockfile to resolve it
    # from, so align the pin with the Nixpkgs pnpm that performs the build.
    # The pin only selects build tooling; it is not embedded in the app.
    patchPhase = ''
      runHook prePatch

      upstreamPin="$(sed -n 's/^[[:space:]]*"packageManager": "pnpm@\([^"]*\)".*/\1/p' package.json)"
      if [ -z "$upstreamPin" ]; then
        echo "package.json no longer pins pnpm; drop the packageManager rewrite" >&2
        exit 1
      fi
      if [ "''${upstreamPin%%.*}" != "${lib.versions.major pnpm_11.version}" ]; then
        echo "upstream pnpm pin $upstreamPin left major ${pnpm_11.version}; review the pnpm toolchain" >&2
        exit 1
      fi
      substituteInPlace package.json \
        --replace-fail '"packageManager": "pnpm@'"$upstreamPin"'"' \
        '"packageManager": "pnpm@${pnpm_11.version}"'

      runHook postPatch
    '';

    # Pinned Electron runtime. The version must match
    # apps/desktop/package.json in the pinned rev so vendored native prebuilds
    # keep their ABI. electron-builder and the electron postinstall resolve
    # downloads through @electron/get, which serves both from its cache
    # directory when the zip and SHASUMS are pre-seeded there. The cache
    # subdirectory is sha256("https://github.com/electron/electron/releases"
    # + "/download/v<electronVersion>") per @electron/get 3.x Cache.js.
    electronDistZip = fetchurl {
      url = source.linux.electronDistUrl;
      hash = source.linux.electronDistHash;
    };
    electronShasums = fetchurl {
      url = source.linux.electronShasumsUrl;
      hash = source.linux.electronShasumsHash;
    };
    # Unpacked Electron headers for node-gyp. @electron/rebuild compiles
    # node-pty (which ships no usable prebuild) against these instead of
    # downloading them.
    electronHeaders = fetchzip {
      url = source.linux.electronHeadersUrl;
      hash = source.linux.electronHeadersHash;
      stripRoot = true;
    };

    nativeBuildInputs = [
      nodejs_24
      pnpm_11
      pnpmConfigHook
      rustPlatform.cargoSetupHook
      cargo
      rustc
      pkg-config
      imagemagick
      (python3.withPackages (ps: [ ps.pyyaml ]))
      unzip
      _7zz
      copyDesktopItems
      makeWrapper
      autoPatchelfHook
      wrapGAppsHook3
    ];

    buildInputs = [
      # libsecret headers for the browser-secret helper compiled by the
      # upstream artifact script.
      libsecret
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
    # Keep the default configure phase (a no-op without a configure script)
    # so pnpmConfigHook still installs node_modules as a postConfigure hook.
    # Preserve the upstream native payload. GNU strip can corrupt or hang on
    # foreign prebuilt objects bundled for other libcs.
    dontStrip = true;
    dontWrapGApps = true;

    env = {
      # Upstream lifecycle scripts assume network access. The build stays
      # offline: pnpm resolves from the vendored store and Electron artifacts
      # come from the pre-seeded @electron/get cache.
      ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
      # Electron Builder 26.15 downloads its own archiver unless this override
      # points to an existing executable. Use Nixpkgs' native 7-Zip instead.
      ELECTRON_BUILDER_7ZIP_PATH = lib.getExe _7zz;
      CARGO_NET_OFFLINE = "true";
      # Release preparation changes manifest versions after the frozen install.
      # pnpm 11 otherwise tries to reinstall before run/exec. Dependencies are
      # already locked and installed; the stage helper preserves that graph.
      pnpm_config_verify_deps_before_run = "false";
      pnpm_config_offline = "true";
      # node-gyp rebuilds (notably node-pty, which ships no Linux prebuild)
      # compile against these headers instead of downloading them.
      npm_config_nodedir = "${finalAttrs.electronHeaders}";
    };

    buildPhase = ''
      runHook preBuild

      # Pin the XDG cache home so every cache lookup below (pnpm aside)
      # resolves deterministically: env-paths prefers it over $HOME, and
      # the sandbox inherits whatever the caller had set.
      export XDG_CACHE_HOME="$HOME/.cache"

      # Seed the @electron/get cache before anything resolves Electron
      # artifacts. @electron/get serves the distribution zip from its
      # cache; the SHASUMS lookup below is patched to do the same instead
      # of re-downloading it on every build.
      electronCacheDir="$XDG_CACHE_HOME/electron/${builtins.hashString "sha256" "https://github.com/electron/electron/releases/download/v${source.linux.electronVersion}"}"
      install -d "$electronCacheDir"
      cp --no-preserve=mode "${finalAttrs.electronDistZip}" \
        "$electronCacheDir/electron-v${source.linux.electronVersion}-linux-x64.zip"
      cp --no-preserve=mode "${finalAttrs.electronShasums}" \
        "$electronCacheDir/SHASUMS256.txt"
      chmod u+rw "$electronCacheDir"/electron-v*.zip "$electronCacheDir"/SHASUMS256.txt
      test -s "$electronCacheDir/electron-v${source.linux.electronVersion}-linux-x64.zip" || {
        echo "electron dist seeding failed for $electronCacheDir" >&2
        exit 1
      }
      test -s "$electronCacheDir/SHASUMS256.txt" || {
        echo "electron SHASUMS seeding failed for $electronCacheDir" >&2
        exit 1
      }

      # @electron/get re-downloads SHASUMS256.txt on every validation
      # (cacheMode Bypass) even when the archive itself is cached. Read it
      # from the pre-seeded cache instead, but keep caller-owned temporary
      # output: ReadOnly copies the hit to a temp dir, which the validation
      # cleanup then removes. (ReadWrite would hand back the cache path
      # itself, and the same cleanup would wipe the whole seeded cache
      # directory.) A missing file or substitution fails the build loudly
      # so an @electron/get major bump gets reviewed instead of silently
      # re-downloading. Only the CJS entry point needs it: electron-builder
      # consumes @electron/get through require().
      # The 3.x glob tracks electron-builder's pinned major; anything else
      # (such as the electron package's own copy) keeps its behavior.
      shopt -s nullglob
      electronGetCopies=(node_modules/.pnpm/@electron+get@3.*/node_modules/@electron/get/dist/cjs/index.js)
      shopt -u nullglob
      if [ "''${#electronGetCopies[@]}" -eq 0 ]; then
        echo "no @electron/get 3.x copy found below node_modules/.pnpm" >&2
        exit 1
      fi
      for electronGet in "''${electronGetCopies[@]}"; do
        substituteInPlace "$electronGet" \
          --replace-fail 'cacheMode: types_1.ElectronDownloadCacheMode.Bypass,' \
          'cacheMode: types_1.ElectronDownloadCacheMode.ReadOnly,'
      done

      # Compile the desktop renderer, the server bundle, and the native
      # helpers through the upstream workspace runner. Lifecycle scripts stay
      # skipped: native prebuilds ship inside the vendored pnpm store.
      # Release tags retain development manifest versions; match upstream's
      # release preparation before bundling server and renderer metadata.
      node scripts/update-release-package-versions.ts ${commonAttrs.version}
      pnpm run build:desktop

      # The artifact script stages a lockfile-less workspace and installs it
      # with `vp install --prod`. That step needs registry metadata (for
      # range resolution) and vp's own managed pnpm (a version download),
      # neither of which exists inside the sandbox. Route exactly that
      # invocation through farm-stage-deps.py instead: it verifies the
      # staged specs against the main lockfile and copies the installed
      # production closure, preserving peer contexts and relative links.
      # Staged pnpm metadata lets electron-builder collect that same tree.
      # Skipping lifecycle scripts is safe here: native prebuilds ship
      # inside their tarballs, the Electron runtime comes from the
      # pre-seeded cache via electron-builder, and sharp (the one
      # downloader left) is only a dependency of the unstaged marketing
      # workspace. Every other vp subcommand (notably
      # `vp exec ... electron-builder`) still runs for real.
      mkdir -p "$PWD/.nix-vpbin"
      cat > "$PWD/.nix-vpbin/vp" <<SHIM
      #!${stdenv.shell}
      set -euo pipefail
      if [ "\$1" = "install" ]; then
        shift
        python3 "\$T3_FARM_STAGE_DEPS" --source-root "\$T3_SOURCE_ROOT" --stage "\$PWD" --lockfile "\$T3_SOURCE_ROOT/pnpm-lock.yaml"
        echo "[stage-farm] top-level entries:"
        ls "\$PWD/node_modules"
        exit 0
      fi
      exec "\$VP_REAL_BIN" "\$@"
      SHIM
      chmod +x "$PWD/.nix-vpbin/vp"
      export VP_REAL_BIN="$PWD/node_modules/.bin/vp"
      export T3_FARM_STAGE_DEPS="${./farm-stage-deps.py}"
      export T3_SOURCE_ROOT="$PWD"
      export PATH="$PWD/.nix-vpbin:$PWD/node_modules/.bin:$PATH"

      # Stage and package with the upstream artifact script. The zip target
      # emits a plain archive of the unpacked tree: unlike dir it is a file
      # artifact (the only kind the script copies to the output directory),
      # and unlike AppImage it needs no extra tooling or FUSE. The install
      # phase unpacks it into a native Nix package below.
      node scripts/build-desktop-artifact.ts \
        --skip-build \
        --build-version ${commonAttrs.version} \
        --platform linux \
        --target zip \
        --arch x64 \
        --output-dir "$PWD/desktop-out"

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      archives=(desktop-out/*.zip)
      if [ "''${#archives[@]}" -ne 1 ]; then
        echo "expected exactly one upstream zip in desktop-out; found:" >&2
        find desktop-out -maxdepth 2 >&2 || true
        exit 1
      fi
      mkdir -p unpacked-tree
      unzip -q "''${archives[0]}" -d unpacked-tree
      appBinary="$(find unpacked-tree -maxdepth 2 -name t3code -type f | head -1)"
      test -n "$appBinary" || {
        echo "no t3code executable below unpacked-tree; found:" >&2
        find unpacked-tree -maxdepth 2 >&2 || true
        exit 1
      }
      unpacked="$(dirname "$appBinary")"

      install -d "$out/lib" "$out/bin" "$out/share/applications" "$out/share/icons/hicolor/512x512/apps"
      cp -a "$unpacked" "$out/lib/${commonAttrs.pname}"
      install -Dm644 LICENSE "$out/share/doc/${commonAttrs.pname}/LICENSE"
      # The Nix desktop entry below is authoritative; drop any staged one so
      # two entries cannot compete for the same application id.
      find "$out/lib/${commonAttrs.pname}" -name '*.desktop' -delete

      # Resize the upstream brand artwork for the desktop entry.
      magick "$PWD/assets/prod/black-universal-1024.png" -resize 512x512 \
        "$out/share/icons/hicolor/512x512/apps/${commonAttrs.pname}.png"

      # No outer FHS/namespace wrapper: retain the host's development setup.
      makeShellWrapper "$out/lib/${commonAttrs.pname}/t3code" "$out/bin/${commonAttrs.pname}" \
        --inherit-argv0 \
        --suffix PATH : ${
          lib.makeBinPath (
            [
              coreutils
              git
              xdg-utils
            ]
            ++ extraPackages
          )
        } \
        --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform=wayland --enable-features=WaylandWindowDecorations,WebRTCPipeWireCapturer --enable-wayland-ime=true}}"

      runHook postInstall
    '';

    # The staged tree bundles prebuilds for other libcs that cannot load on
    # this glibc system; keeping them preserves the upstream payload while
    # autoPatchelf only rewrites what this package actually loads.
    autoPatchelfIgnoreMissingDeps = [ "libc.musl-*.so.*" ];

    postFixup = ''
      wrapGApp "$out/bin/${commonAttrs.pname}"
    '';

    desktopItems = [
      (makeDesktopItem {
        name = commonAttrs.pname;
        desktopName = source.appName;
        comment = commonAttrs.meta.description;
        exec = "${commonAttrs.pname} %U";
        terminal = false;
        icon = commonAttrs.pname;
        startupWMClass = "t3code";
        categories = [ "Development" ];
        mimeTypes = [
          "x-scheme-handler/t3code"
          "x-scheme-handler/t3code-dev"
        ];
      })
    ];

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      test -x "$out/bin/${commonAttrs.pname}"
      test -f "$out/lib/${commonAttrs.pname}/resources/app.asar"
      test -f "$out/share/applications/${commonAttrs.pname}.desktop"
      test -s "$out/share/icons/hicolor/512x512/apps/${commonAttrs.pname}.png"
      ELECTRON_RUN_AS_NODE=1 "$out/lib/${commonAttrs.pname}/t3code" \
        ${./check-runtime.cjs} "$out/lib/${commonAttrs.pname}/resources" ${commonAttrs.version}
      serverVersion="$(T3CODE_HOME="$TMPDIR/t3-check" ELECTRON_RUN_AS_NODE=1 \
        "$out/lib/${commonAttrs.pname}/t3code" \
        "$out/lib/${commonAttrs.pname}/resources/app.asar/apps/server/dist/bin.mjs" --version)"
      test "$serverVersion" = "t3 v${commonAttrs.version}"
      runHook postInstallCheck
    '';
  }
)
