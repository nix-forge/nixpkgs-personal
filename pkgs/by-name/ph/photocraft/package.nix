{
  replaceVars,
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
  mesa,
  wayland,
  libxkbcommon,
  libx11,
  libxcursor,
  libxi,
  libxrandr,
  fontconfig,
  dbus,
  xdg-utils,
  cups,
  rcodesign,
}:
let
  source = import ./source.nix;
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
  pname = "photocraft";
  inherit (source) version;
  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = lib.mapAttrs (_: dependency: dependency.hash) source.gitDependencies;
  };
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "photocraft";
    inherit (source) rev hash;
  };
  # Upstream embeds every manifest font but registers only Japanese fonts.
  patches = [
    ./register-all-craft-fonts.patch
    ./headless-shortcut-test.patch
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ ./statm-rss-sampling.patch ];
  strictDeps = true;
  checkType = "debug";
  # This native integration test requires macOS services outside the build sandbox.
  # Its original assertions are retained in the separately compiled host artifact.
  checkFlags = lib.optionals stdenv.hostPlatform.isDarwin [
    "--skip"
    "swap_arrow::tests::rendered_glyph_has_a_left_head_and_a_lower_right_head"
  ];
  # Library tests use synthetic servers on loopback; external networking stays blocked.
  __darwinAllowLocalNetworking = stdenv.buildPlatform.isDarwin;

  cargoBuildFlags = [
    "-p"
    "photocraft"
    "-p"
    "photocraft-cli"
    "--locked"
  ];
  cargoTestFlags = [
    "--workspace"
    "--lib"
    "--exclude"
    "photocraft-web"
    "--exclude"
    "xtask"
    "--locked"
  ];
  buildFeatures = [
    "photocraft/heif"
    "photocraft-cli/heif"
  ];

  # The Metal policy regression is a GUI binary test, outside the workspace --lib suite.
  # A Darwin cross builder can compile this test; a native Intel builder also runs it.
  postBuild = lib.optionalString (
    stdenv.hostPlatform.isDarwin
    && stdenv.hostPlatform.isx86_64
    && stdenv.buildPlatform.system != stdenv.hostPlatform.system
  ) (builtins.readFile ./check-gpu-policy.sh);
  postCheck = lib.optionalString (
    stdenv.hostPlatform.isDarwin
    && stdenv.hostPlatform.isx86_64
    && stdenv.buildPlatform.system == stdenv.hostPlatform.system
  ) (builtins.readFile ./check-gpu-policy.sh);

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    python3
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ rcodesign ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ ];
  env = {
    PHOTOCRAFT_BUILD_SHA = source.rev;
    CRAFT_FONTS_DIR = fonts;
    CRAFT_FONTS_REQUIRED = "1";
  }
  // lib.optionalAttrs (stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isx86_64) {
    ARTCRAFT_RUST_TARGET = stdenv.hostPlatform.rust.rustcTarget;
    ARTCRAFT_GPU_POLICY_COMPILE_ONLY =
      if stdenv.buildPlatform.system == stdenv.hostPlatform.system then "0" else "1";
  };

  # The offscreen raster regression can use Lavapipe inside a Linux sandbox.
  nativeCheckInputs =
    lib.optionals (stdenv.hostPlatform.isLinux && stdenv.buildPlatform.canExecute stdenv.hostPlatform)
      [
        mesa
        vulkan-loader
      ];
  preCheck =
    builtins.readFile ./scripts/pre-check.sh
    +
      lib.optionalString
        (stdenv.hostPlatform.isLinux && stdenv.buildPlatform.canExecute stdenv.hostPlatform)
        ''
          source ${
            replaceVars ./scripts/check-software-vulkan.sh {
              vulkanLibraryPath = lib.makeLibraryPath [ vulkan-loader ];
              driverManifest = "${mesa}/share/vulkan/icd.d/lvp_icd.${
                if stdenv.hostPlatform.isx86_64 then "x86_64" else "aarch64"
              }.json";
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
          cups
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
  passthru.hostTests =
    lib.optionalAttrs
      (stdenv.hostPlatform.isDarwin && stdenv.buildPlatform.system == stdenv.hostPlatform.system)
      {
        native = import ./scripts/native-host-tests.nix {
          inherit
            lib
            stdenv
            replaceVars
            rust
            source
            gitSources
            ;
          inherit fonts;
          package = finalAttrs.finalPackage;
          crate = "photocraft-ui-egui";
          testName = "swap_arrow::tests::rendered_glyph_has_a_left_head_and_a_lower_right_head";
        };
      };
  meta = {
    description = "Native image editor with layered PSD documents and automation";
    homepage = "https://github.com/storytold/photocraft";
    maintainers = [
      {
        # Keep public attribution stable across Nixpkgs maintainer registries.
        github = "IanHollow";
        githubId = 72767437;
        name = "IanHollow";
      }
    ];
    changelog = "https://github.com/storytold/photocraft/releases/tag/v${source.upstreamVersion}";
    license =
      with lib.licenses;
      AND (
        [
          (OR [
            mit
            asl20
          ])
          ofl
          bitstreamVera
          ufl
          zlib # Statically linked foldhash in the native wgpu graph.
          isc
          bsd3 # The pinned winprint dependency.
          cc-by-30
          cc0
        ]
        ++ [
          {
            licenseType = "simple";
            fullName = "SCOWL word list license";
            shortName = "SCOWL";
            url = "https://github.com/storytold/photocraft/blob/${source.rev}/assets/dict/LICENSE-SCOWL.txt";
            free = true;
            redistributable = true;
          }
        ]
      );
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
    mainProgram = "photocraft";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  }
  // lib.optionalAttrs (
    stdenv.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "PhotoCraft.app"; };
})
