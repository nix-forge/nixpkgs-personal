{
  replaceVars,
  callPackage,
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  fetchgit,
  pkg-config,
  makeWrapper,
  python3,
  runCommand,
  appstream,
  desktop-file-utils,
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
  rcodesign,
  alsa-lib,
  ffmpeg,
  cacert,
}:
let
  source = import ./source.nix;
  rustcryptoSource = callPackage ./rustcrypto-source.nix { };
  zipSource = callPackage ./zip-source.nix { patches = [ ./zip-header-identity.patch ]; };
  candleSource = callPackage ./candle-source.nix { patches = [ ./candle-zip-compatibility.patch ]; };
  gitSources = lib.mapAttrs (
    _: dependency: fetchgit { inherit (dependency) url rev hash; }
  ) source.gitDependencies;
  fonts = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    inherit (source.fonts) rev hash;
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
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "filmcraft";
  inherit (source) version;
  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = lib.mapAttrs (_: dependency: dependency.hash) source.gitDependencies;
  };
  cargoPatches = [ ./rustls-security-update.patch ];
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "filmcraft";
    inherit (source) rev hash;
  };
  strictDeps = true;
  checkType = "debug";
  # Library tests use synthetic servers on loopback; external networking stays blocked.
  __darwinAllowLocalNetworking = stdenv.buildPlatform.isDarwin;

  cargoBuildFlags = [
    "-p"
    "filmcraft"
    "-p"
    "filmcraft-cli"
    "--locked"
  ];
  cargoTestFlags = [
    "--workspace"
    "--lib"
    "--exclude"
    "filmcraft-web"
    "--exclude"
    "xtask"
    "--locked"
  ];
  buildFeatures = [
    "filmcraft/whisper"
    "filmcraft-cli/whisper"
  ];
  patches = [
    ./archive-security.patch
    ./rustcrypto-provider.patch
    ./disable-unused-gtk-menu-features.patch
    ./remove-restricted-marks.patch

  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ ./system-font-fixture.patch ]
  ++ [ ./japanese-font-test-system-fallbacks.patch ];

  postPatch = ''
    cmp Cargo.lock ${./Cargo.lock}
    mkdir -p vendor
    cp -R ${zipSource} vendor/zip
    cp -R ${rustcryptoSource} vendor/rustls-rustcrypto
    cp -R ${candleSource} vendor/candle-core
    chmod -R u+w vendor
  '';

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    python3
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ rcodesign ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ alsa-lib ];
  nativeCheckInputs = [ ffmpeg ];
  env.FILMCRAFT_BUILD_SHA = source.rev;
  env.CRAFT_FONTS_DIR = fonts;
  env.CRAFT_FONTS_REQUIRED = "1";

  preCheck = builtins.readFile ./scripts/pre-check.sh;

  postInstall = ''
    source ${
      replaceVars ./scripts/install-git-notices.sh {
        inherit (finalAttrs) pname;
        gitSources = lib.escapeShellArgs (lib.attrValues gitSources);
        gitMetadata = builtins.toFile "artcraft-git-sources.json" (builtins.toJSON source.gitDependencies);
      }
    }
    source ${
      replaceVars ./scripts/post-install.sh {
        inherit (finalAttrs) pname;
        inherit fonts;
        inherit (finalAttrs) cargoDeps;
      }
    }
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    source ${
      replaceVars ./scripts/linux-install-desktop-assets.sh {
        inherit (source) releaseDate releaseType;
        inherit (finalAttrs) pname;
        inherit (finalAttrs) version;
        runtimeLibraryPath = lib.makeLibraryPath runtimeLibraries;
        desktopToolsPath = lib.makeBinPath [
          xdg-utils
          fontconfig
        ];
        inherit cacert;
      }
    }
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    source ${
      replaceVars ./scripts/darwin-install-app-bundle.sh {
        inherit (finalAttrs) version;
        source_upstreamVersion = source.upstreamVersion;
        source_rev = source.rev;
        deploymentTargetFlags =
          if lib.versionAtLeast stdenv.hostPlatform.darwinMinVersion "11.0" then
            stdenv.hostPlatform.darwinMinVersion
          else
            "11.0";
      }
    }
  '';

  # Sign after fixup, which may rewrite Mach-O load commands.
  # Cross builds use the nativeBuildInputs signing tool from PATH.
  postFixup = lib.optionalString stdenv.hostPlatform.isDarwin ''
    source ${
      replaceVars ./scripts/post-fixup.sh {
        cliCommand =
          if stdenv.buildPlatform.system == stdenv.hostPlatform.system then
            lib.getExe rcodesign
          else
            "rcodesign";
      }
    }
  '';
  nativeInstallCheckInputs = lib.optionals stdenv.hostPlatform.isLinux [ desktop-file-utils ];
  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        inherit (finalAttrs) pname;
      }
    }
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    desktop-file-validate "$out/share/applications/ai.storyteller.${finalAttrs.pname}.desktop"
    python3 ${./scripts/check_desktop_entry.py} "$out" "ai.storyteller.${finalAttrs.pname}.desktop" "${finalAttrs.pname}"
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    source ${
      replaceVars ./scripts/darwin-check-app-bundle.sh {
        tests_check_craft_assets_py = "${./scripts/check_craft_assets.py}";
        upstreamVersion = lib.escapeShellArg source.upstreamVersion;
      }
    }
  ''
  + (builtins.readFile ./scripts/run-post-install-check-hook.sh);
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

      # Exercise optional voices and Candle eager/lazy tensor archive readers.
      archiveCompatibility = finalAttrs.finalPackage.overrideAttrs (previous: {
        pname = "filmcraft-archive-compatibility";
        cargoBuildType = "debug";
        cargoCheckType = "debug";
        env = previous.env // {
          CARGO_INCREMENTAL = "0";
          CARGO_PROFILE_DEV_DEBUG = "0";
          CARGO_PROFILE_TEST_DEBUG = "0";
        };
        cargoBuildFeatures = [ "kokoro" ];
        cargoCheckFeatures = [ "kokoro" ];
        cargoBuildFlags = [
          "-p"
          "filmcraft-tts"
          "--lib"
          "--locked"
        ];
        cargoTestFlags = [
          "-p"
          "filmcraft-tts"
          "--lib"
          "--locked"
        ];
        installPhase = ''
          runHook preInstall
          mkdir -p "$out"
          touch "$out/passed"
          runHook postInstall
        '';
        postInstall = "";
        postFixup = "";
        doInstallCheck = false;
        passthru = { };
      });

      menuDependencies = finalAttrs.finalPackage.overrideAttrs (_: {
        pname = "filmcraft-menu-dependencies";
        buildPhase = ''
          runHook preBuild
          for configuration in normal neural-voices; do
            features="filmcraft/whisper,filmcraft-cli/whisper"
            if [ "$configuration" = neural-voices ]; then
              features="$features,filmcraft/neural-voices"
            fi
            for target in x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu aarch64-apple-darwin x86_64-apple-darwin x86_64-pc-windows-msvc wasm32-unknown-unknown; do
              cargo metadata --offline --locked --format-version 1 --filter-platform "$target" --features "$features" > "metadata-$configuration-$target.json"
              python3 ${./check_menu_dependencies.py} "metadata-$configuration-$target.json" "$target"
            done
          done
          runHook postBuild
        '';
        checkPhase = ''
          runHook preCheck
          # Check both owning binaries, including the target-selected native menu backend.
          cargo check --offline --locked --package filmcraft --package filmcraft-cli --bins --features "filmcraft/whisper,filmcraft-cli/whisper"
          runHook postCheck
        '';
        doCheck = true;
        preCheck = "";
        installPhase = ''
          runHook preInstall
          mkdir -p "$out"
          cp metadata-*.json "$out/"
          runHook postInstall
        '';
        postInstall = "";
        postFixup = "";
        doInstallCheck = false;
        passthru = { };
      });

      tlsProvider = finalAttrs.finalPackage.overrideAttrs (_: {
        pname = "filmcraft-tls-provider";
        cargoBuildType = "debug";
        cargoCheckType = "debug";
        buildFeatures = [
          "filmcraft-speech/whisper"
          "filmcraft-speech/download"
        ];
        cargoBuildFeatures = [
          "filmcraft-speech/whisper"
          "filmcraft-speech/download"
        ];
        cargoCheckFeatures = [
          "filmcraft-speech/whisper"
          "filmcraft-speech/download"
        ];
        cargoBuildFlags = [
          "-p"
          "filmcraft-speech"
          "--lib"
          "--locked"
        ];
        cargoTestFlags = [
          "-p"
          "filmcraft-speech"
          "--lib"
          "--locked"
        ];
        postCheck = ''
          for target in x86_64-unknown-linux-gnu aarch64-apple-darwin wasm32-unknown-unknown; do
            cargo metadata --offline --locked --format-version 1 --filter-platform "$target" --features "filmcraft/whisper,filmcraft-cli/whisper,filmcraft-speech/download" > "metadata-$target.json"
            python3 ${./check_tls_provider.py} "metadata-$target.json" "$target"
          done
          cargo tree --offline --locked --package filmcraft-speech --no-default-features --target wasm32-unknown-unknown --edges normal,build,dev --prefix none --format '{p}' > speech-web-tree.txt
          python3 ${./check_tls_provider.py} --speech-web-tree speech-web-tree.txt
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p "$out"
          cp metadata-*.json speech-web-tree.txt "$out/"
          runHook postInstall
        '';
        postInstall = "";
        postFixup = "";
        doInstallCheck = false;
        passthru = { };
      });

      licenses = runCommand "${finalAttrs.pname}-font-notices" { nativeBuildInputs = [ python3 ]; } ''
        python3 ${./check_licenses.py} ${finalAttrs.finalPackage} ${finalAttrs.cargoDeps} ${finalAttrs.pname}
        touch "$out"
      '';

    }
    // lib.optionalAttrs (stdenv.buildPlatform.canExecute stdenv.hostPlatform) {
      cli = runCommand "${finalAttrs.pname}-cli-smoke" { nativeBuildInputs = [ python3 ]; } ''
        source ${
          replaceVars ./scripts/cli-smoke.sh {
            package = finalAttrs.finalPackage;
            inherit (finalAttrs) pname;
            darwinCliCheck = lib.optionalString stdenv.hostPlatform.isDarwin ''
              python3 ${./scripts/check_craft_assets.py} bundle ${lib.escapeShellArg (toString finalAttrs.finalPackage)} ${lib.escapeShellArg source.upstreamVersion} ${lib.escapeShellArg stdenv.hostPlatform.darwinMinVersion}
            '';
            tests_check_craft_assets_py = "${./scripts/check_craft_assets.py}";
          }
        }
      '';
    };
  meta = {
    description = "Native nonlinear video editor with timeline and media codecs";
    homepage = "https://github.com/storytold/filmcraft";
    maintainers = [
      {
        # Keep public attribution stable across Nixpkgs maintainer registries.
        github = "IanHollow";
        githubId = 72767437;
        name = "IanHollow";
      }
    ];
    changelog = "https://github.com/storytold/filmcraft/releases/tag/v${source.upstreamVersion}";
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
        mpl20
      ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
    mainProgram = "filmcraft";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  }
  // lib.optionalAttrs (
    stdenv.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "FilmCraft.app"; };
})
