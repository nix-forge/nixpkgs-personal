{
  replaceVars,
  lib,
  stdenv,
  fetchFromGitHub,
  yarn-berry_4-fetcher,
  srcOnly,
  nodejs_26,
  makeWrapper,
  pkg-config,
  python3,
  cairo,
  pango,
  libjpeg,
  giflib,
  pixman,
  librsvg,
  vips,
  coreutils,
  findutils,
  gnused,
}:
let
  source = import ./source.nix;
  nodejs =
    assert lib.assertMsg (lib.versionAtLeast nodejs_26.version "26.12.0")
      "Maintainerr requires Nixpkgs Node 26.12.0+ with the V8 ARM header fix";
    nodejs_26;
  yarn = "${nodejs}/bin/node $(find .yarn/releases -maxdepth 1 -name 'yarn-*.cjs' -print -quit)";
in
assert lib.assertMsg (lib.versionAtLeast vips.version "8.18.7")
  "Maintainerr sharp requires Nixpkgs libvips 8.18.7+";
stdenv.mkDerivation (finalAttrs: {
  pname = "maintainerr";
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "Maintainerr";
    repo = "Maintainerr";
    inherit (source) rev hash;
  };

  missingHashes = ./missing-hashes.json;

  offlineCache = yarn-berry_4-fetcher.fetchYarnBerryDeps {
    yarnLock = "${finalAttrs.src}/yarn.lock";
    inherit (finalAttrs) missingHashes;
    hash = source.yarnHash;
  };

  strictDeps = true;

  nativeBuildInputs = [
    nodejs
    makeWrapper
    pkg-config
    python3
  ];

  buildInputs = [
    cairo
    pango
    libjpeg
    giflib
    pixman
    librsvg
    vips
  ];

  # Compile Node addons against the pinned Nix libraries. Upstream's npm
  # prebuilds target conventional FHS distributions and cannot be used as-is.
  env = {
    npm_config_build_from_source = "true";
    TURBO_TELEMETRY_DISABLED = "1";
    UV_USE_IO_URING = "0";
    YARN_ENABLE_NETWORK = "0";
    YARN_ENABLE_TELEMETRY = "0";
  };

  postPatch = ''
    source ${
      replaceVars ./scripts/post-patch.sh {
        manifestProgram = "${./scripts/patch-manifest.mts}";
      }
    }
  '';

  configurePhase = ''
    source ${
      replaceVars ./scripts/configure-phase.sh {
        inherit (finalAttrs) offlineCache;
        srcOnly_nodejs = srcOnly nodejs;
        inherit nodejs;
        inherit yarn;
      }
    }
  '';

  buildPhase = ''
    source ${replaceVars ./scripts/build-phase.sh { inherit yarn; }}
  '';

  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        stdenv_shell = stdenv.shell;
        buildToolsPath = lib.makeBinPath [
          nodejs
          coreutils
          findutils
          gnused
        ];
      }
    }
  '';

  passthru = {
    upstreamRevision = source.rev;
  };

  meta = {
    description = "Media-library maintenance web application";
    homepage = "https://maintainerr.info/";
    changelog = "https://github.com/Maintainerr/Maintainerr/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "maintainerr";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
