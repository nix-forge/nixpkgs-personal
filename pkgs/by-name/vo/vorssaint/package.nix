{
  callPackage,
  replaceVars,
  lib,
  stdenv,
  fetchFromGitHub,
  coreutils,
  findutils,
  imagemagick,
  makeWrapper,
  python3,
  rcodesign,
  sqlite,
  swift,
}:

let
  pname = "vorssaint";
  source = import ./source.nix;
in
stdenv.mkDerivation (finalAttrs: {
  inherit pname;
  inherit (source) version;

  src = fetchFromGitHub source.src;

  patches = [ ];
  postPatch = ''
    source ${
      replaceVars ./scripts/post-patch.sh {
        rebrand_py = "${./rebrand.py}";
      }
    }
  '';
  patchFlags = [
    "-p1"
    "--fuzz=0"
  ];

  nativeBuildInputs = [
    coreutils
    findutils
    imagemagick
    makeWrapper
    python3
    rcodesign
    swift
  ];
  buildInputs = [ sqlite ];
  strictDeps = true;

  dontConfigure = true;

  buildPhase = ''
    source ${
      replaceVars ./scripts/build-phase.sh {
        icon_svg = "${./icon.svg}";
        menu_icon_svg = "${./menu-bar-icon.svg}";
        pythonCheck1 = "${./scripts/build_icns_icon.py}";
        sqliteOverlay = ./write_sqlite_overlay.py;
        sqliteHeaders = "${lib.getDev sqlite}/include";
        sqliteLibraryPath = "${lib.getLib sqlite}/lib";
        sqliteCheck = ./check_sqlite.swift;
        deploymentTarget = ./scripts/read_deployment_target.py;

      }
    }
  '';

  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        inherit pname;
        readme = "${./README.md}";
      }
    }
  '';

  # ServiceManagement requires the main app, its privileged helper and their
  # resources to be sealed as a single bundle. rcodesign provides a reproducible
  # ad-hoc signature; a public Nix derivation cannot embed a private Developer ID.
  postFixup = ''
    source ${
      replaceVars ./scripts/post-fixup.sh {
        rcodesign = lib.getExe rcodesign;
      }
    }
  '';

  nativeInstallCheckInputs = [ python3 ];
  postInstallCheck = ''
    python3 ${./scripts/check_app_bundle.py} "$out/Applications/PersonalMonitor.app" --expected-version ${lib.escapeShellArg source.version}
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        check_bundle_py = "${./check_bundle.py}";
        check_menu_bar_icon = ./check_menu_bar_icon.swift;
      }
    }
  '';

  passthru = {
    appName = "PersonalMonitor";
    updateScript = [
      (lib.getExe (callPackage ./update.nix { }))
      "--source-directory"
      (builtins.unsafeDiscardStringContext (toString ./.))
    ];
  };

  meta = {
    description = "Unofficial macOS system monitoring toolkit built from Vorssaint";
    homepage = "https://vorssaint.com/";
    downloadPage = "https://github.com/vorssaint/vorssaint-utils/releases";
    changelog = "https://github.com/vorssaint/vorssaint-utils/releases/tag/v${finalAttrs.version}";
    license = [
      lib.licenses.gpl3Plus
      lib.licenses.mit
    ];
    mainProgram = "vorssaint";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  }
  // lib.optionalAttrs (
    stdenv.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "PersonalMonitor.app"; };
})
