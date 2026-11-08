{
  replaceVars,
  lib,
  stdenv,
  buildPackages,
  rustPlatform,
  fetchFromGitHub,
  fetchgit,
  fetchurl,
  pkg-config,
  libiconv,
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
  cups,
  rcodesign,
  sway,
  wl-clipboard,
  wayland-utils,
}:
let
  source = import ./source.nix;
  gitSources = lib.mapAttrs (
    _: dependency: fetchgit { inherit (dependency) url rev hash; }
  ) source.gitDependencies;
  upstreamFonts = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    inherit (source.fonts) rev hash;
  };
  # PdfCraft forbids Source Han-derived visual assets, including Noto CJK.
  # Keep allowed Japanese/Arabic faces and use the original Apache-licensed Droid face.
  fonts = runCommand "pdfcraft-policy-fonts" { nativeBuildInputs = [ python3 ]; } ''
    CRAFT_FONTS_REVISION=${lib.escapeShellArg source.fonts.rev} python3 ${./select_fonts.py} ${upstreamFonts} ${fetchurl source.droid.font} ${fetchurl source.droid.notice} ${fetchurl source.thai.font} ${fetchurl source.thai.notice} "$out"
  '';
  # Upstream ATTRIBUTION.toml pins these redistributable CC-BY-SA models.
  ocrModels = runCommand "pdfcraft-ocr-models" { } ''
    source ${
      replaceVars ./scripts/install-ocr-models.sh {
        fetchurl_source_ocr_detection = fetchurl source.ocr.detection;
        fetchurl_source_ocr_recognition = fetchurl source.ocr.recognition;
        fetchurl_source_ocr_license = fetchurl source.ocr.license;
      }
    }
  '';
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
  pname = "pdfcraft";
  inherit (source) version;
  cargoLock = {
    lockFile = if stdenv.hostPlatform.isLinux then ./Cargo-linux.lock else ./Cargo.lock;
    outputHashes = lib.mapAttrs (_: dependency: dependency.hash) source.gitDependencies;
  };
  # Keep the Linux clipboard backend feature and its dependency closure locked.
  cargoPatches = [
    ./rustls-security-update.patch
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ ./native-wayland-clipboard.patch ];
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "pdfcraft";
    inherit (source) rev hash;
  };
  strictDeps = true;
  # Native transport regressions use synthetic localhost servers.
  __darwinAllowLocalNetworking = stdenv.buildPlatform.isDarwin;
  checkType = "debug";

  # Rust 1.98.1 rejects RTen's AVX-512 VNNI intrinsic signature on x86.
  # Patch the vendored crate without changing Cargo.lock or disabling OCR/SIMD.
  postPatch = lib.optionalString stdenv.hostPlatform.isx86_64 ''
    source ${
      replaceVars ./scripts/post-patch.sh {
        rten_vnni_intrinsic_patch = "${./rten-vnni-intrinsic.patch}";
        tests_update_vendor_checksum_py = "${./scripts/update_vendor_checksum.py}";
      }
    }
  '';

  cargoBuildFlags = [
    "-p"
    "pdfcraft"
    "-p"
    "pdfcraft-cli"
    "--locked"
  ];
  cargoTestFlags = [
    "--workspace"
    "--lib"
    "--exclude"
    "pdfcraft-web"
    "--exclude"
    "xtask"
    "--locked"
  ];
  patches = [
    ./remove-restricted-marks.patch
    ./font-input-attribution.patch
    ./native-script-fonts.patch
    ./ocr-fixture-resolution.patch
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ ./native-wayland-clipboard-fixture.patch ];

  nativeBuildInputs = [
    pkg-config
    makeWrapper
    python3
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ rcodesign ];
  # AWS-LC's Cargo build script links the build machine's Rust standard library.
  # Register the native compiler hooks as well as its iconv dependency.
  depsBuildBuild =
    lib.optionals
      (stdenv.buildPlatform.isDarwin && stdenv.buildPlatform.system != stdenv.hostPlatform.system)
      [
        buildPackages.stdenv.cc
        libiconv
      ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ ];
  env.PDFCRAFT_BUILD_SHA = source.rev;
  env.CRAFT_FONTS_DIR = fonts;
  env.CRAFT_FONTS_REQUIRED = "1";
  env.PDFCRAFT_MODELS = ocrModels;

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
        inherit ocrModels;
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
        inherit ocrModels;
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

      fonts =
        runCommand "pdfcraft-font-policy"
          {
            nativeBuildInputs = [
              (python3.withPackages (p: [ p.fonttools ]))
              buildPackages.patch
            ];
          }
          ''
                python3 ${./check_fonts.py} ${fonts} ${finalAttrs.src}/crates/ui-egui/src/i18n
            cp ${finalAttrs.src}/ATTRIBUTION.{toml,md} .
            patch -p1 < ${./font-input-attribution.patch}
            python3 ${./check_attribution.py} ${finalAttrs.src} .
                touch "$out"
          '';

    }
    //
      lib.optionalAttrs
        (stdenv.hostPlatform.isLinux && stdenv.buildPlatform.canExecute stdenv.hostPlatform)
        {
          waylandClipboard = import ./wayland-clipboard-test.nix {
            inherit
              replaceVars
              lib
              stdenv
              runCommand
              python3
              sway
              wl-clipboard
              wayland-utils
              dbus
              fontconfig
              runtimeLibraries
              fonts
              ocrModels
              ;
            package = finalAttrs.finalPackage;
            runner = ./run_sway_clipboard.py;
            runnerTests = ./test_sway_clipboard_runner.py;
            fixture = ./clipboard-fixture.png;
          };
        }
    // lib.optionalAttrs (stdenv.buildPlatform.canExecute stdenv.hostPlatform) {
      cli = runCommand "${finalAttrs.pname}-cli-smoke" { nativeBuildInputs = [ python3 ]; } ''
        source ${
          replaceVars ./scripts/cli-smoke.sh {
            package = finalAttrs.finalPackage;
            inherit (finalAttrs) pname;
            darwinCliCheck = lib.optionalString stdenv.hostPlatform.isDarwin ''
              python3 ${./scripts/check_craft_assets.py} bundle ${lib.escapeShellArg (toString finalAttrs.finalPackage)} ${lib.escapeShellArg source.upstreamVersion} ${lib.escapeShellArg stdenv.hostPlatform.darwinMinVersion} --pdf-models
            '';
            scripts_package_check_py = "${./scripts/create_pdf_fixture.py}";
            tests_check_craft_assets_py = "${./scripts/check_craft_assets.py}";
          }
        }
      '';
    };
  meta = {
    description = "PDF workbench with editing, rendering and document automation";
    homepage = "https://github.com/storytold/pdfcraft";
    maintainers = [
      {
        # Keep public attribution stable across Nixpkgs maintainer registries.
        github = "IanHollow";
        githubId = 72767437;
        name = "IanHollow";
      }
    ];
    changelog = "https://github.com/storytold/pdfcraft/releases/tag/v${source.upstreamVersion}";
    license =
      with lib.licenses;
      AND [
        (OR [
          mit
          asl20
        ])
        asl20 # Droid Sans Fallback, independently of the application license choice.
        ofl
        bitstreamVera
        ufl
        zlib # Statically linked foldhash in the native wgpu graph.
        bsd3
        cc0
        cc-by-sa-40
        isc
      ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
    mainProgram = "pdfcraft";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  }
  // lib.optionalAttrs (
    stdenv.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "PdfCraft.app"; };
})
