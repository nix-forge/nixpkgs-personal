{
  replaceVars,
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
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
  pname = "figcraft";
  inherit (source) version;
  cargoPatches = [ ./rustls-security-update.patch ];
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "figcraft";
    inherit (source) rev hash;
  };
  cargoLock.lockFile = ./Cargo.lock;
  strictDeps = true;
  # Native collaboration/control regressions bind synthetic loopback sockets.
  __darwinAllowLocalNetworking = stdenv.buildPlatform.isDarwin;
  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  checkType = "debug";
  # The stable release includes the bounded ruzstd decoder.
  # Keep the application and vendored dependency locks identical.
  patches = [

    ./native-window-app-id.patch
    ./nix-fontconfig-discovery.patch
    ./portable-ui-regressions.patch
  ];
  cargoBuildFlags = [
    "-p"
    "figcraft"
    "-p"
    "figcraft-cli"
    "-p"
    "figcraft-server"
    "--locked"
  ];
  cargoTestFlags = [
    "--workspace"
    "--lib"
    "--exclude"
    "figcraft-web"
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
  env = {
    FIGCRAFT_BUILD_SHA = source.rev;
    CRAFT_FONTS_DIR = fonts;
    CRAFT_FONTS_REQUIRED = "1";
    FIGCRAFT_EMBED_CJK = "1";
  }
  // lib.optionalAttrs stdenv.hostPlatform.isLinux {
    FIGCRAFT_FC_LIST = "${fontconfig}/bin/fc-list";
  };
  postPatch = ''
    cmp Cargo.lock ${./Cargo.lock}
    python3 ${./scripts/check_fonts.py} input ${fonts}
  '';
  preCheck = builtins.readFile ./scripts/pre-check.sh;
  postInstall = ''
    source ${
      replaceVars ./scripts/post-install.sh {
        inherit (finalAttrs) pname cargoDeps;
        inherit fonts;
      }
    }
    python3 ${./scripts}/write_provenance.py ${fonts} ${./source.nix} "$out/share/doc/figcraft" ${lib.escapeShellArg source.rev} ${lib.escapeShellArg source.hash} ${lib.escapeShellArg source.fonts.rev} ${lib.escapeShellArg source.fonts.hash}
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    source ${
      replaceVars ./scripts/linux-install-desktop-assets.sh {
        inherit (source) releaseDate releaseType;
        inherit (finalAttrs) pname version;
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
        makeIcns = ./scripts/make_icns.py;
        deploymentTargetFlags =
          if lib.versionAtLeast stdenv.hostPlatform.darwinMinVersion "11.0" then
            stdenv.hostPlatform.darwinMinVersion
          else
            "11.0";
      }
    }
  '';
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
    source ${replaceVars ./scripts/install-check-phase.sh { inherit (finalAttrs) pname; }}
    python3 ${./scripts/check_fonts.py} installed ${fonts} "$out"
  ''
  + lib.optionalString stdenv.hostPlatform.isLinux ''
    desktop-file-validate "$out/share/applications/ai.storyteller.figcraft.desktop"
    python3 ${./scripts/check_desktop_entry.py} "$out" ai.storyteller.figcraft.desktop figcraft
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    source ${
      replaceVars ./scripts/darwin-check-app-bundle.sh {
        tests_check_craft_assets_py = "${./scripts/check_craft_assets.py}";
        upstreamVersion = lib.escapeShellArg source.upstreamVersion;
      }
    }
    python3 ${./scripts}/check_bundle.py "$out" ${source.upstreamVersion} ${stdenv.hostPlatform.darwinMinVersion}
  ''
  + builtins.readFile ./scripts/run-post-install-check-hook.sh;
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
      licenses = runCommand "figcraft-font-notices" { nativeBuildInputs = [ python3 ]; } ''
        python3 ${./check_licenses.py} ${finalAttrs.finalPackage} ${finalAttrs.cargoDeps} figcraft
        python3 ${./scripts/check_fonts.py} installed ${fonts} ${finalAttrs.finalPackage}
        touch "$out"
      '';
    }
    // lib.optionalAttrs (stdenv.buildPlatform.canExecute stdenv.hostPlatform) {
      cli = runCommand "figcraft-cli-roundtrip" { nativeBuildInputs = [ python3 ]; } ''
        export HOME="$TMPDIR" FIGCRAFT_NO_SYSTEM_FONTS=1
        python3 ${./scripts}/check_cli.py ${finalAttrs.finalPackage} ${./scripts/document.json} ${source.version}
        touch "$out"
      '';
      server =
        runCommand "figcraft-server-smoke"
          {
            nativeBuildInputs = [ python3 ];
            __darwinAllowLocalNetworking = stdenv.buildPlatform.isDarwin;
          }
          ''
            export HOME="$TMPDIR"
            python3 ${./scripts/check_server.py} ${finalAttrs.finalPackage} ${source.version}
            touch "$out"
          '';
    };
  meta = {
    description = "Interface design and prototyping editor with CLI and collaboration server";
    homepage = "https://github.com/storytold/figcraft";
    changelog = "https://github.com/storytold/figcraft/releases/tag/v${source.upstreamVersion}";
    maintainers = [
      {
        github = "IanHollow";
        githubId = 72767437;
        name = "IanHollow";
      }
    ];
    license =
      with lib.licenses;
      AND [
        (OR [
          mit
          asl20
        ])
        mit # Embedded egui font/icon assets also carry their own MIT notices.
        ofl
        bitstreamVera
        ufl
        zlib # Statically linked foldhash in the native wgpu graph.
        cc0 # Upstream AppStream metadata.
      ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
    mainProgram = "figcraft";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  }
  // lib.optionalAttrs (
    stdenv.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "FigCraft.app"; };
})
