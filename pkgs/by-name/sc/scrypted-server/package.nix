{
  replaceVars,
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_24,
  python3,
  pkg-config,
  vips,
}:
let
  source = import ./source.nix;
in
buildNpmPackage (finalAttrs: {
  pname = "scrypted-server";
  inherit (source) version npmDepsHash;

  src = fetchFromGitHub {
    owner = "koush";
    repo = "scrypted";
    tag = "v${finalAttrs.version}";
    inherit (source) hash;
  };
  sourceRoot = "source/server";

  postPatch = ''
    source ${
      replaceVars ./scripts/post-patch.sh {
        inherit nodejs_24;
        package_lock_json = "${./package-lock.json}";
        manifestProgram = "${./scripts/patch-manifest.mts}";

      }
    }
  '';

  nodejs = nodejs_24;
  strictDeps = true;
  npmFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [
    python3
    pkg-config
  ];
  buildInputs = [ vips ];
  env = {
    npm_config_build_from_source = "true";
    SHARP_FORCE_GLOBAL_LIBVIPS = "1";
  };
  buildPhase = builtins.readFile ./scripts/build-phase.sh;

  # The upstream postinstall downloads a Python interpreter and ffmpeg-static
  # downloads a binary. Both are supplied by Nix at runtime instead.
  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        launcherSource = replaceVars ./scripts/scrypted-serve.sh.in {
          inherit nodejs_24;
          runtimeOutput = null;
        };
        inherit nodejs_24;
      }
    }
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        inherit nodejs_24;
        nodeModulesCheck = "${./scripts/check_node_modules.mts}";

      }
    }
  '';

  meta = {
    description = "Scrypted home video integration server";
    homepage = "https://github.com/koush/scrypted";
    license = lib.licenses.isc;
    platforms = lib.platforms.linux;
    mainProgram = "scrypted-serve";
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
