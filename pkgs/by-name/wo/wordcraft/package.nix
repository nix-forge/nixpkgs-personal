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
  mesa,
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
  espeak-ng,
  alsa-plugins,
  ffmpeg,
  rcodesign,
}:
let
  source = import ./source.nix;
  zipSource = callPackage ./zip-source.nix { patches = [ ./zip-header-identity.patch ]; };
  gitSources = lib.mapAttrs (
    _: dependency: fetchgit { inherit (dependency) url rev hash; }
  ) source.gitDependencies;
  fonts = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    inherit (source.fonts) rev hash;
  };
  # ALSA's libav codec plugin needs no ffplay/SDL GUI build prerequisites.
  # Keep every codec/device flag and the speech engine's audio support intact.
  speechEngine =
    if stdenv.hostPlatform.isLinux && !stdenv.buildPlatform.canExecute stdenv.hostPlatform then
      espeak-ng.override {
        alsa-plugins = alsa-plugins.override {
          ffmpeg = ffmpeg.override {
            withSdl2 = false;
            buildFfplay = false;
          };
        };
      }
    else
      espeak-ng;
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
  pname = "wordcraft";
  inherit (source) version;
  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = lib.mapAttrs (_: dependency: dependency.hash) source.gitDependencies;
  };
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "wordcraft";
    inherit (source) rev hash;
  };
  patches = [
    ./archive-security.patch
    ./bounded-format-probe.patch
    ./chrome-focus-before-typing.patch
    ./register-all-craft-fonts.patch
    ./optional-thai-cache-miss-fixture.patch
  ];
  strictDeps = true;
  # Native MCP and Zotero regressions use synthetic localhost servers.
  __darwinAllowLocalNetworking = stdenv.buildPlatform.isDarwin;
  checkType = "debug";

  cargoBuildFlags = [
    "-p"
    "wordcraft"
    "-p"
    "wordcraft-cli"
    "--locked"
  ];
  cargoTestFlags = [
    "--workspace"
    "--lib"
    "--exclude"
    "wordcraft-web"
    "--exclude"
    "xtask"
    "--locked"
  ];

  postPatch = ''
    cmp Cargo.lock ${./Cargo.lock}
    mkdir -p vendor
    cp -R ${zipSource} vendor/zip
    chmod -R u+w vendor/zip
  '';

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    python3
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ rcodesign ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ ];
  env.WORDCRAFT_BUILD_SHA = source.rev;
  env.CRAFT_FONTS_DIR = fonts;
  env.CRAFT_FONTS_REQUIRED = "1";

  # Canvas assertions use Mesa's CPU adapter on headless Linux builders.
  checkInputs = lib.optionals stdenv.hostPlatform.isLinux [
    mesa
    vulkan-loader
    libGL
  ];
  preCheck =
    builtins.readFile ./scripts/pre-check.sh
    + lib.optionalString stdenv.hostPlatform.isLinux ''
      source ${
        replaceVars ./scripts/linux-check-renderer.sh {
          softwareRendererLibraryPath = lib.makeLibraryPath [
            mesa
            vulkan-loader
            libGL
          ];
          inherit mesa;
          vulkanIcdArchitecture = stdenv.hostPlatform.parsed.cpu.name;
        }
      }
    '';

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
          fontconfig
          xdg-utils
          speechEngine
        ];
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

      # Run complete owning-crate regressions without launching the GUI.
      archiveCompatibility = finalAttrs.finalPackage.overrideAttrs (previous: {
        pname = "wordcraft-archive-compatibility";
        cargoBuildType = "debug";
        cargoCheckType = "debug";
        env = previous.env // {
          CARGO_INCREMENTAL = "0";
          CARGO_PROFILE_DEV_DEBUG = "0";
          CARGO_PROFILE_TEST_DEBUG = "0";
        };
        cargoBuildFeatures = [ ];
        cargoCheckFeatures = [ ];
        cargoBuildFlags = [
          "-p"
          "wordcraft-docx"
          "-p"
          "wordcraft-formats"
          "-p"
          "wordcraft-engine"
          "--lib"
          "--tests"
          "--locked"
        ];
        cargoTestFlags = [
          "-p"
          "wordcraft-docx"
          "-p"
          "wordcraft-formats"
          "-p"
          "wordcraft-engine"
          "--lib"
          "--tests"
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
            linuxSpeechCheck = lib.optionalString stdenv.hostPlatform.isLinux ''
              ${lib.getExe speechEngine} -w spoken.wav 'Hello Nix'
              python3 ${./scripts/check_craft_assets.py} wav spoken.wav
            '';
          }
        }
      '';
    };
  meta = {
    description = "Word processor with DOCX interchange and PDF export";
    homepage = "https://github.com/storytold/wordcraft";
    maintainers = [
      {
        # Keep public attribution stable across Nixpkgs maintainer registries.
        github = "IanHollow";
        githubId = 72767437;
        name = "IanHollow";
      }
    ];
    changelog = "https://github.com/storytold/wordcraft/releases/tag/v${source.upstreamVersion}";
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
        bsd3
        cc0
      ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
    mainProgram = "wordcraft";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  }
  // lib.optionalAttrs (
    stdenv.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "WordCraft.app"; };
})
