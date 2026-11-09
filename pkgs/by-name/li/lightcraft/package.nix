{
  replaceVars,
  callPackage,
  lib,
  stdenv,
  rustPlatform,
  rust,
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
}:
let
  source = import ./source.nix;
  rustcryptoSource = callPackage ./rustcrypto-source.nix { };
  zipSource = callPackage ./zip-source.nix { patches = [ ./zip-header-identity.patch ]; };
  candleSource = callPackage ./candle-source.nix {
    patches = [ ./candle-zip-compatibility.patch ];
    # Preserve the no-GPU CPU fallback in the explicit source, before Cargo uses it.
    postPatch = lib.optionalString stdenv.hostPlatform.isDarwin ''
      patch --fuzz=0 -p2 < ${./candle-metal-device-bounds.patch}
    '';
  };
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
  pname = "lightcraft";
  inherit (source) version;
  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = lib.mapAttrs (_: dependency: dependency.hash) source.gitDependencies;
  };
  cargoPatches = [ ./rustls-security-update.patch ];
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "lightcraft";
    inherit (source) rev hash;
  };
  patches = [
    ./archive-security.patch
    ./rustcrypto-provider.patch
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    ./appstream-screenshot.patch
    ./heif-mime-types.patch
  ];
  strictDeps = true;
  checkType = "debug";
  # Library tests use synthetic servers on loopback; external networking stays blocked.
  __darwinAllowLocalNetworking = stdenv.buildPlatform.isDarwin;

  postPatch = ''
    cmp Cargo.lock ${./Cargo.lock}
    mkdir -p vendor
    cp -R ${zipSource} vendor/zip
    cp -R ${rustcryptoSource} vendor/rustls-rustcrypto
    cp -R ${candleSource} vendor/candle-core
    chmod -R u+w vendor
  '';

  cargoBuildFlags = [
    "-p"
    "lightcraft"
    "-p"
    "lightcraft-cli"
    "--locked"
  ];
  cargoTestFlags = [
    "--workspace"
    "--lib"
    "--exclude"
    "lightcraft-web"
    "--exclude"
    "xtask"
    "--locked"
  ];
  buildFeatures = [
    "lightcraft/heif"
    "lightcraft-cli/heif"
  ];
  # Synthetic HEIF codec regressions live outside the ordinary library suite.
  postCheck = ''
    source ${
      replaceVars ./scripts/check-heif.sh {
        rustTarget = stdenv.hostPlatform.rust.rustcTargetSpec;
        cargoEnvironment = rust.envVars.setEnv;
      }
    }
  '';

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    python3
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ rcodesign ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ ];
  env.LIGHTCRAFT_BUILD_SHA = source.rev;
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
  passthru.mkEmulatedUiTest = import ./scripts/emulated-ui-test.nix;
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

      # Keep safetensors loading and CPU inference compatible with the patched dependency.
      segmentCompatibility = finalAttrs.finalPackage.overrideAttrs (previous: {
        pname = "lightcraft-segment-compatibility";
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
          "lightcraft-segment"
          "--lib"
          "--locked"
        ];
        cargoTestFlags = [
          "-p"
          "lightcraft-segment"
          "--lib"
          "--locked"
        ];
        postCheck = "";
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

      tlsProvider = finalAttrs.finalPackage.overrideAttrs (_: {
        pname = "lightcraft-tls-provider";
        cargoBuildType = "debug";
        cargoCheckType = "debug";
        buildFeatures = [ ];
        cargoBuildFeatures = [ ];
        cargoCheckFeatures = [ ];
        cargoBuildFlags = [
          "-p"
          "lightcraft-fetch"
          "--lib"
          "--locked"
        ];
        cargoTestFlags = [
          "-p"
          "lightcraft-fetch"
          "--lib"
          "--locked"
        ];
        postCheck = ''
          for target in x86_64-unknown-linux-gnu aarch64-apple-darwin wasm32-unknown-unknown; do
            cargo metadata --offline --locked --format-version 1 --filter-platform "$target" --features "lightcraft/heif,lightcraft-cli/heif" > "metadata-$target.json"
            python3 ${./check_tls_provider.py} "metadata-$target.json" "$target"
          done
        '';
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
    description = "Photo library and RAW image developer";
    homepage = "https://github.com/storytold/lightcraft";
    maintainers = [
      {
        # Keep public attribution stable across Nixpkgs maintainer registries.
        github = "IanHollow";
        githubId = 72767437;
        name = "IanHollow";
      }
    ];
    changelog = "https://github.com/storytold/lightcraft/releases/tag/v${source.upstreamVersion}";
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
    mainProgram = "lightcraft";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  }
  // lib.optionalAttrs (
    stdenv.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "LightCraft.app"; };
})
