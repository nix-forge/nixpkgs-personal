{
  replaceVars,
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
}:
let
  source = import ./source.nix;
  gitSources = lib.mapAttrs (
    _: dependency: fetchgit { inherit (dependency) url rev hash; }
  ) source.gitDependencies;
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
  pname = "gridcraft";
  inherit (source) version;
  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = lib.mapAttrs (_: dependency: dependency.hash) source.gitDependencies;
  };
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "gridcraft";
    inherit (source) rev hash;
  };
  strictDeps = true;
  checkType = "debug";
  # Library tests use synthetic servers on loopback; external networking stays blocked.
  __darwinAllowLocalNetworking = stdenv.buildPlatform.isDarwin;

  cargoBuildFlags = [
    "-p"
    "gridcraft"
    "-p"
    "gridcraft-cli"
    "--locked"
  ];
  cargoTestFlags = [
    "--workspace"
    "--lib"
    "--exclude"
    "gridcraft-web"
    "--exclude"
    "xtask"
    "--locked"
  ];

  patches = lib.optionals stdenv.hostPlatform.isLinux [ ./appstream-screenshot.patch ];

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    python3
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ rcodesign ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ ];
  env.GRIDCRAFT_BUILD_SHA = source.rev;

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
            scripts_package_check_pyjson_py = "${./scripts/check_formula_result.py}";
            scripts_package_check_pycsv_py = "${./scripts/check_workbook_roundtrip.py}";
          }
        }
      '';
    };
  meta = {
    description = "Spreadsheet editor with formulas and XLSX interchange";
    homepage = "https://github.com/storytold/gridcraft";
    maintainers = [
      {
        # Keep public attribution stable across Nixpkgs maintainer registries.
        github = "IanHollow";
        githubId = 72767437;
        name = "IanHollow";
      }
    ];
    changelog = "https://github.com/storytold/gridcraft/releases/tag/v${source.upstreamVersion}";
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
      ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
    mainProgram = "gridcraft";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  }
  // lib.optionalAttrs (
    stdenv.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "GridCraft.app"; };
})
