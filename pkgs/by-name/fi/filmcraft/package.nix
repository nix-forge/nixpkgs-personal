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
    libxcb
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
    ./cargo-release-manifest.patch
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ ./system-font-fixture.patch ]
  ++ [ ./japanese-font-test-system-fallbacks.patch ];

  postPatch = ''
    cp ${./Cargo.lock} Cargo.lock
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
  ++ lib.optionals stdenv.hostPlatform.isLinux [ wayland-scanner ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ rcodesign ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    alsa-lib
    libxcb
    wayland
  ];
  nativeCheckInputs = [ ffmpeg ];
  env = {
    FILMCRAFT_BUILD_SHA = source.rev;
    CRAFT_FONTS_DIR = fonts;
    CRAFT_FONTS_REQUIRED = "1";
  };

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
