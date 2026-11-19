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
  mesa,
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
  cups,
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
  pname = "designcraft";
  inherit (source) version;
  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = lib.mapAttrs (_: dependency: dependency.hash) source.gitDependencies;
  };
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "designcraft";
    inherit (source) rev hash;
  };
  strictDeps = true;
  checkType = "debug";
  # Library tests use synthetic servers on loopback; external networking stays blocked.
  __darwinAllowLocalNetworking = stdenv.buildPlatform.isDarwin;

  cargoBuildFlags = [
    "-p"
    "designcraft"
    "-p"
    "designcraft-cli"
    "--locked"
  ];
  cargoTestFlags = [
    "--workspace"
    "--lib"
    "--exclude"
    "designcraft-web"
    "--exclude"
    "xtask"
    "--locked"
  ];
  patches = [
    ./remove-restricted-marks.patch
    ./register-all-craft-fonts.patch
    ./macos-shortcuts-and-fonts.patch
    ./archive-security.patch
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ ./appstream-screenshot.patch ];

  # Keep the source and vendor lock on the same reviewed ZIP release.
  postPatch = ''
    cp ${./Cargo.lock} Cargo.lock
    mkdir -p vendor
    cp -R ${zipSource} vendor/zip
    chmod -R u+w vendor/zip
  '';

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
    DESIGNCRAFT_BUILD_SHA = source.rev;
    CRAFT_FONTS_DIR = fonts;
    CRAFT_FONTS_REQUIRED = "1";
  };

  preCheck =
    builtins.readFile ./scripts/pre-check.sh
    + lib.optionalString stdenv.hostPlatform.isLinux ''
      # The native pixel regression needs a Vulkan adapter in the sandbox.
      export LD_LIBRARY_PATH="${
        lib.makeLibraryPath [ vulkan-loader ]
      }''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      export VK_DRIVER_FILES="${mesa}/share/vulkan/icd.d/lvp_icd.${stdenv.hostPlatform.parsed.cpu.name}.json"
      export XDG_RUNTIME_DIR="$TMPDIR"
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
  meta = {
    description = "Page layout and publishing editor";
    homepage = "https://github.com/storytold/designcraft";
    maintainers = [
      {
        # Keep public attribution stable across Nixpkgs maintainer registries.
        github = "IanHollow";
        githubId = 72767437;
        name = "IanHollow";
      }
    ];
    changelog = "https://github.com/storytold/designcraft/releases/tag/v${source.upstreamVersion}";
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
    mainProgram = "designcraft";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  }
  // lib.optionalAttrs (
    stdenv.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "DesignCraft.app"; };
})
