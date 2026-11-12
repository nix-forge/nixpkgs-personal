{
  replaceVars,
  lib,
  stdenv,
  rustPlatform,
  rust,
  fetchFromGitHub,
  fetchgit,
  fetchurl,
  coreutils,
  noto-fonts-cjk-sans,
  pkg-config,
  makeWrapper,
  python3,
  runCommand,
  appstream,
  writers,
  librsvg,
  resvg,
  desktop-file-utils,
  copyDesktopItems,
  makeDesktopItem,
  libGL,
  vulkan-loader,
  wayland,
  libxkbcommon,
  libx11,
  libxcursor,
  libxi,
  libxrandr,
  fontconfig,
  dbus,
  xdg-utils,
  procps,
  appimage-run,
  pkgs,
  cacert,
  rcodesign,
}:
let
  source = import ./source.nix;
  appimageRuntime = import ./appimage-cross-runtime.nix {
    inherit
      lib
      pkgs
      appimage-run
      stdenv
      ;
  };
  gitSources = lib.mapAttrs (
    _: dependency: fetchgit { inherit (dependency) url rev hash; }
  ) source.gitDependencies;
  inherit (source) releaseDate;
  fonts = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    inherit (source.fonts) rev hash;
  };
  japaneseFontLicense = fetchurl {
    url = "https://raw.githubusercontent.com/notofonts/noto-cjk/523d033d6cb47f4a80c58a35753646f5c3608a78/LICENSE";
    hash = "sha256-anP5VBwt50FYwOfPawpY73dPWngL8ZHy1+ycxT7+K/I=";
  };
  runtimeLibraries = [
    libGL
    vulkan-loader
    wayland
    libxkbcommon
    libx11
    libxcursor
    libxi
    libxrandr
    fontconfig
    dbus.lib
  ];
  appId =
    if stdenv.hostPlatform.isLinux then
      "io.github.nix_forge.craft-launcher"
    else
      "io.github.nix-forge.craft-launcher";
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "craft-launcher";
  inherit (source) version;
  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = lib.mapAttrs (_: dependency: dependency.hash) source.gitDependencies;
  };
  cargoPatches = [ ./rustls-security-update.patch ];
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-launcher";
    inherit (source) rev hash;
  };
  strictDeps = true;
  __darwinAllowLocalNetworking = stdenv.buildPlatform.isDarwin;
  checkType = "debug";
  cargoBuildFlags = [
    "-p"
    "artcraft-launcher"
    "--locked"
  ];
  cargoTestFlags = [
    "--workspace"
    "--lib"
    "--bins"
    "--exclude"
    "artcraft-launcher-web"
    "--exclude"
    "xtask"
    "--locked"
  ];
  # Apple disk-image/signing services and process inspection are unavailable
  # in the Darwin sandbox. Retain these tests in hostTests below.
  checkFlags = lib.optionals stdenv.hostPlatform.isDarwin [
    "--skip"
    "install::tests::macos_checks::only_the_teams_signature_passes"
    "--skip"
    "install::tests::macos_checks::the_bundle_must_be_the_releases_version"
    "--skip"
    "install::tests::macos_checks::an_unsigned_update_leaves_the_installed_copy_alone"
    "--skip"
    "self_update::tests::the_new_bundle_replaces_the_running_one"
    "--skip"
    "process::tests::running_paths_are_matched_literally"
  ];
  patches = [
    ./remove-restricted-marks.patch
    ./nix-managed-applications.patch
    ./nix-cjk-fonts.patch
    ./autostart-exec-quoting.patch
    ./nix-bundle-integration.patch
    ./nix-discovery-priority.patch
    ./unix-restart-test-path-helpers.patch
    ./nix-linux-process-locale.patch
    ./disable-unused-gtk-tray-features.patch
    ./macos-quit-handshake.patch
    ./preserve-update-backups-upstream-a2e490.patch
    ./atomic-state-upstream-314.patch
    ./appimage-runtime-and-safe-refresh.patch
  ];
  nativeBuildInputs = [
    pkg-config
    makeWrapper
    python3
    # The font-free SVG avoids Darwin CoreText dependencies with resvg.
    (if stdenv.hostPlatform.isDarwin then resvg else librsvg)
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ rcodesign ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ copyDesktopItems ];
  desktopItems = lib.optionals stdenv.hostPlatform.isLinux [
    (makeDesktopItem {
      name = appId;
      desktopName = "Craft Launcher";
      genericName = "Application manager";
      comment = finalAttrs.meta.description;
      exec = finalAttrs.pname;
      tryExec = finalAttrs.pname;
      icon = appId;
      terminal = false;
      categories = [
        "Settings"
        "PackageManager"
      ];
      startupWMClass = appId;
    })
  ];
  nativeCheckInputs = lib.optionals stdenv.hostPlatform.isLinux [ procps ];
  env = {
    CRAFT_LAUNCHER_CJK_FONT = "${fonts}/fonts/noto-sans-cjk-sc/NotoSansCJKsc-Regular.otf";
    CRAFT_LAUNCHER_JAPANESE_FONT = "${noto-fonts-cjk-sans}/share/fonts/opentype/noto-cjk/NotoSansCJK-VF.otf.ttc";
  }
  // lib.optionalAttrs stdenv.hostPlatform.isLinux {
    CRAFT_LAUNCHER_APPIMAGE_RUN = lib.getExe appimageRuntime;
    CRAFT_LAUNCHER_ENV = lib.getExe' coreutils "env";
  };
  postPatch = ''
    # The package lock also prunes GTK dependencies after disabling tray defaults.
    cp ${./Cargo.lock} Cargo.lock
    substituteInPlace crates/native/src/nix.rs --replace-fail '@nixStoreDir@' '${builtins.storeDir}'
    rm -rf docs/brand assets/app-icon
    mkdir -p nix-assets
    cp ${./icon.svg} nix-assets/icon.svg
    for size in 44 64 256 1024; do
      ${
        if stdenv.hostPlatform.isDarwin then
          ''resvg --width "$size" --height "$size" nix-assets/icon.svg "nix-assets/icon-$size.png"''
        else
          ''rsvg-convert -w "$size" -h "$size" nix-assets/icon.svg > "nix-assets/icon-$size.png"''
      }
    done
    python3 ${./make_icns.py} nix-assets/icon-1024.png nix-assets/icon.icns
  '';
  preBuild = lib.optionalString stdenv.hostPlatform.isLinux ''
    # current_exe() sees makeWrapper's hidden binary; autostart must use the wrapper.
    export CRAFT_LAUNCHER_WRAPPER="$out/bin/craft-launcher"
  '';
  preCheck = ''
    export CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
  '';
  postInstall = ''
    source ${
      replaceVars ./scripts/install-git-notices.sh {
        inherit (finalAttrs) pname;
        gitSources = lib.escapeShellArgs (lib.attrValues gitSources);
        gitMetadata = builtins.toFile "artcraft-git-sources.json" (builtins.toJSON source.gitDependencies);
      }
    }
    mv "$out/bin/artcraft-launcher" "$out/bin/craft-launcher"
    mkdir -p "$out/share/doc/craft-launcher/licenses"
    find -L . -type f \( -iname '*license*' -o -iname '*attribution*' -o -name 'OFL*' -o -name 'UFL*' -o -name 'Hack-Regular.txt' -o -name 'NOTICE*' -o -name 'COPYING*' \) \
      -not -path './target/*' -print0 | while IFS= read -r -d "" notice; do
        install -Dm644 "$notice" "$out/share/doc/craft-launcher/licenses/$notice"
      done
    (
      cd ${finalAttrs.cargoDeps}
      find -L . -type f \( -iname '*license*' -o -name 'OFL*' -o -name 'UFL*' -o -name 'Hack-Regular.txt' -o -name 'NOTICE*' -o -name 'COPYING*' \) \
        -print0 | while IFS= read -r -d "" notice; do
          install -Dm644 "$notice" "$out/share/doc/craft-launcher/licenses/dependencies/$notice"
        done
    )
    install -Dm644 ${fonts}/fonts/noto-sans-cjk-sc/OFL.txt "$out/share/doc/craft-launcher/licenses/noto-sans-cjk-sc/OFL.txt"
    install -Dm644 ${fonts}/ATTRIBUTION.md "$out/share/doc/craft-launcher/licenses/craft-fonts-ATTRIBUTION.md"
    install -Dm644 ${japaneseFontLicense} "$out/share/doc/craft-launcher/licenses/noto-sans-cjk-jp/OFL.txt"
    printf '%s\n' 'Built from source with Nix. Restricted ArtCraft graphical marks were removed and replaced with an original neutral icon. This modified distribution is called Craft Launcher. Nix-managed applications are read-only to the launcher; update them through your Nix configuration.' \
      > "$out/share/doc/craft-launcher/PACKAGING-NOTICE"
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    install -Dm644 nix-assets/icon.svg "$out/share/icons/hicolor/scalable/apps/${appId}.svg"
    for size in 64 256; do
      install -Dm644 "nix-assets/icon-$size.png" "$out/share/icons/hicolor/''${size}x''${size}/apps/${appId}.png"
    done
    mkdir -p "$out/share/applications" "$out/share/metainfo"
    bash ${./scripts/install-legacy-icon-aliases.sh} "$out" "${appId}"

    cat > "$out/share/metainfo/${appId}.metainfo.xml" <<EOF
    <?xml version="1.0" encoding="UTF-8"?>
    <component type="desktop-application">
      <id>${appId}</id><name>Craft Launcher</name>
      <summary>Manage the Craft application suite</summary>
      <metadata_license>CC0-1.0</metadata_license><project_license>MIT OR Apache-2.0</project_license>
      <description><p>A desktop launcher for discovering and managing Craft applications. Nix-managed installations are launched without changing their immutable packages.</p></description>
      <launchable type="desktop-id">${appId}.desktop</launchable>
      <url type="homepage">https://github.com/storytold/craft-launcher</url>
      <provides><binary>craft-launcher</binary></provides>
      <releases><release version="${finalAttrs.version}" date="${releaseDate}" type="${source.releaseType}"/></releases>
    </component>
    EOF
    wrapProgram "$out/bin/craft-launcher" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath runtimeLibraries}" \
      --prefix PATH : "${
        lib.makeBinPath [
          fontconfig
          xdg-utils
          procps
          desktop-file-utils
        ]
      }" \
      --set-default SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt"
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    app="$out/Applications/Craft Launcher.app/Contents"
    mkdir -p "$app/MacOS" "$app/Resources"
    mv "$out/bin/craft-launcher" "$app/MacOS/craft-launcher"
    ln -s "../Applications/Craft Launcher.app/Contents/MacOS/craft-launcher" "$out/bin/craft-launcher"
    cp nix-assets/icon.icns "$app/Resources/CraftLauncher.icns"
    cp -r "$out/share/doc/craft-launcher/licenses" "$app/Resources/Licenses"
    python3 ${./make_plist.py} "$app/Info.plist" '${source.upstreamVersion}' '${source.rev}' '${stdenv.hostPlatform.darwinMinVersion}'
    printf 'APPL????' > "$app/PkgInfo"
  '';
  postFixup = lib.optionalString stdenv.hostPlatform.isDarwin ''
    ${
      if stdenv.buildPlatform.system == stdenv.hostPlatform.system then
        lib.getExe rcodesign
      else
        "rcodesign"
    } sign "$out/Applications/Craft Launcher.app"
  '';
  nativeInstallCheckInputs = lib.optionals stdenv.hostPlatform.isLinux [ desktop-file-utils ];
  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/craft-launcher" --version)" = 'craft-launcher ${source.upstreamVersion}'
    test -s "$out/share/doc/craft-launcher/licenses/LICENSE-MIT"
    test -s "$out/share/doc/craft-launcher/licenses/noto-sans-cjk-sc/OFL.txt"
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    desktop-file-validate "$out/share/applications/${appId}.desktop"
    python3 ${./scripts/check_desktop_entry.py} "$out" "${appId}.desktop" "craft-launcher"
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    test -s "$out/Applications/Craft Launcher.app/Contents/_CodeSignature/CodeResources"
  ''
  + ''
    runHook postInstallCheck
  '';
  passthru.tests =
    (import ./scripts/appstream-test.nix {
      inherit
        lib
        stdenv
        runCommand
        appstream
        ;
      package = finalAttrs.finalPackage;
    })
    // {

      licenses = runCommand "${finalAttrs.pname}-font-notices" { nativeBuildInputs = [ python3 ]; } ''
        python3 ${./check_licenses.py} ${finalAttrs.finalPackage} ${finalAttrs.cargoDeps} ${finalAttrs.pname}
        cmp ${japaneseFontLicense} ${finalAttrs.finalPackage}/share/doc/craft-launcher/licenses/noto-sans-cjk-jp/OFL.txt
        touch "$out"
      '';
    }
    // lib.optionalAttrs (
      stdenv.hostPlatform.isLinux && lib.versions.major pkgs.gcc.cc.version == "16"
    ) { appimageRuntime = import ./appimage-runtime-test.nix { inherit pkgs appimageRuntime; }; }
    // lib.optionalAttrs (stdenv.buildPlatform.canExecute stdenv.hostPlatform) {
      cli =
        let
          check = writers.writePython3Bin "check-craft-launcher" {
            libraries = [ python3.pkgs.defusedxml ];
            flakeIgnore = [ "E501" ];
          } ./check_cli.py;
          minimumVersion =
            if stdenv.hostPlatform.isDarwin then
              if lib.versionAtLeast stdenv.hostPlatform.darwinMinVersion "11.0" then
                stdenv.hostPlatform.darwinMinVersion
              else
                "11.0"
            else
              "0";
        in
        runCommand "craft-launcher-version-smoke" { } ''
          source ${
            replaceVars ./check-cli.sh {
              launcher = lib.escapeShellArg (lib.getExe finalAttrs.finalPackage);
              check = lib.escapeShellArg (lib.getExe check);
              arguments = lib.escapeShellArgs [
                (toString finalAttrs.finalPackage)
                source.upstreamVersion
                finalAttrs.version
                appId
                source.rev
                (if stdenv.hostPlatform.isDarwin then "darwin" else "linux")
                minimumVersion
              ];
            }
          }
        '';
    }
    // lib.optionalAttrs (stdenv.buildPlatform.system == stdenv.hostPlatform.system) {
      quitState = import ./scripts/quit-state-test.nix {
        inherit lib stdenv rustPlatform;
        source = gitSources."craft-quit-0.1.0";
      };
    };
  # Build an artifact for explicit native macOS checks outside the sandbox.
  # These tests use temporary bundles, never the user's Applications folder.
  passthru.hostTests =
    lib.optionalAttrs
      (stdenv.hostPlatform.isDarwin && stdenv.buildPlatform.system == stdenv.hostPlatform.system)
      {
        native = import ./scripts/native-host-tests.nix {
          inherit
            lib
            stdenv
            replaceVars
            source
            gitSources
            fonts
            japaneseFontLicense
            ;
          inherit rust;
          package = finalAttrs.finalPackage;
        };
      };
  meta = {
    description = "Desktop launcher for the Craft creative and office applications";
    homepage = "https://github.com/storytold/craft-launcher";
    maintainers = [
      {
        # Keep public attribution stable across Nixpkgs maintainer registries.
        github = "IanHollow";
        githubId = 72767437;
        name = "IanHollow";
      }
    ];
    changelog = "https://github.com/storytold/craft-launcher/releases/tag/v${source.upstreamVersion}";
    license =
      with lib.licenses;
      AND [
        (OR [
          mit
          asl20
        ])
        ofl
        bitstreamVera
        ufl
        zlib # Statically linked foldhash in the native wgpu graph.
        cc0
        cc-by-40
      ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
    mainProgram = "craft-launcher";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  }
  // lib.optionalAttrs (
    stdenv.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "Craft Launcher.app"; };
})
