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
  libGL,
  vulkan-loader,
  wayland,
  wayland-scanner,
  libxkbcommon,
  libx11,
  libxcb,
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
    libxcb
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
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "figcraft";
    inherit (source) rev hash;
  };
  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = lib.mapAttrs (_: dependency: dependency.hash) source.gitDependencies;
  };
  strictDeps = true;
  # Native collaboration/control regressions bind synthetic loopback sockets.
  __darwinAllowLocalNetworking = stdenv.buildPlatform.isDarwin;
  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  checkType = "debug";
  # The stable release includes the bounded ruzstd decoder.
  # Keep the application and vendored dependency locks identical.
  patches = [
    ./archive-security.patch
    ./embedded-font-fallbacks.patch
    ./home-recents-failure-context.patch
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
  ++ lib.optionals stdenv.hostPlatform.isLinux [ wayland-scanner ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ rcodesign ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    libxcb
    wayland
  ];
  env = {
    FIGCRAFT_BUILD_SHA = source.rev;
    CRAFT_FONTS_DIR = fonts;
    CRAFT_FONTS_REQUIRED = "1";
    FIGCRAFT_EMBED_CJK = "1";
  };
  postPatch = ''
    cp ${./Cargo.lock} Cargo.lock
    mkdir -p vendor
    cp -R ${zipSource} vendor/zip
    chmod -R u+w vendor/zip
    python3 ${./scripts/check_fonts.py} input ${fonts}
  '';
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
