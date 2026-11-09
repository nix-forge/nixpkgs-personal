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
  mesa,
}:
let
  source = import ./source.nix;
  epaintSource = callPackage ./epaint-source.nix { };
  zipSource = callPackage ./zip-source.nix { patches = [ ./zip-header-identity.patch ]; };
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
  pname = "deckcraft";
  inherit (source) version;
  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = lib.mapAttrs (_: dependency: dependency.hash) source.gitDependencies;
  };
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "deckcraft";
    inherit (source) rev hash;
  };
  patches = [
    ./approved-ui-fonts.patch
    ./archive-security.patch
    ./symbol-font-unicode.patch
    ./ui-glyph-presence.patch
    ./bounded-ui-font-fallback.patch
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ ./appstream-screenshot.patch ];
  # Keep local dependency sources and the font-policy lock synchronized.
  postPatch = ''
    cp ${./Cargo.lock} Cargo.lock
    mkdir -p vendor
    cp -R ${zipSource} vendor/zip
    cp -R ${epaintSource} vendor/epaint
    chmod -R u+w vendor/zip vendor/epaint
  '';
  strictDeps = true;
  checkType = "debug";

  cargoBuildFlags = [
    "-p"
    "deckcraft"
    "-p"
    "deckcraft-cli"
    "--locked"
  ];
  cargoTestFlags = [
    "--workspace"
    "--lib"
    "--exclude"
    "deckcraft-web"
    "--exclude"
    "xtask"
    "--locked"
  ];

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    python3
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ rcodesign ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ alsa-lib ];
  nativeCheckInputs = [ ffmpeg ];
  env.DECKCRAFT_BUILD_SHA = source.rev;
  env.CRAFT_FONTS_DIR = fonts;
  env.CRAFT_FONTS_REQUIRED = "1";

  # The canvas regressions need a real adapter in headless Linux builders.
  # Match the repository GUI checks' Mesa software-rendering environment.
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
          xdg-utils
          fontconfig
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

      licenses = runCommand "${finalAttrs.pname}-font-notices" { nativeBuildInputs = [ python3 ]; } ''
        python3 ${./check_licenses.py} ${finalAttrs.finalPackage} ${finalAttrs.cargoDeps} ${finalAttrs.pname}
        touch "$out"
      '';

      # The normal workspace --lib suite does not run PPTX integration tests.
      archiveCompatibility = finalAttrs.finalPackage.overrideAttrs (_: {
        pname = "deckcraft-archive-compatibility";
        cargoBuildType = "debug";
        cargoCheckType = "debug";
        cargoBuildFlags = [
          "-p"
          "deckcraft-format"
          "-p"
          "deckcraft-pptx"
          "--locked"
        ];
        cargoTestFlags = [
          "-p"
          "deckcraft-format"
          "-p"
          "deckcraft-pptx"
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

      fontPolicy = runCommand "deckcraft-font-policy" { nativeBuildInputs = [ python3 ]; } ''
        python3 ${./check_font_policy.py} ${finalAttrs.finalPackage} ${finalAttrs.cargoDeps}
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
    description = "Presentation editor with PPTX interchange and media playback";
    homepage = "https://github.com/storytold/deckcraft";
    maintainers = [
      {
        # Keep public attribution stable across Nixpkgs maintainer registries.
        github = "IanHollow";
        githubId = 72767437;
        name = "IanHollow";
      }
    ];
    changelog = "https://github.com/storytold/deckcraft/releases/tag/v${source.upstreamVersion}";
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
        mpl20
        (lib.licenses.mkLicense {
          shortName = "Unicode-Symbol-2011";
          fullName = "Unicode Symbol mapping data license (2011)";
          url = "https://www.unicode.org/Public/MAPPINGS/VENDORS/ADOBE/symbol.txt";
          free = true;
          redistributable = true;
        })
      ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
    mainProgram = "deckcraft";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  }
  // lib.optionalAttrs (
    stdenv.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "DeckCraft.app"; };
})
