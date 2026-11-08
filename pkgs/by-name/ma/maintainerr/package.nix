{
  replaceVars,
  lib,
  stdenv,
  fetchFromGitHub,
  yarn-berry_4-fetcher,
  srcOnly,
  nodejs_26,
  nodejs-slim_26,
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
  # sharp 0.35.5 requires at least libvips 8.18.7. Current Nixpkgs provides
  # it; retain the backport only for standalone consumers with older pins.
  currentVips =
    if lib.versionAtLeast vips.version "8.18.7" then
      vips
    else
      vips.overrideAttrs (_: {
        version = "8.18.7";
        src = fetchFromGitHub {
          owner = "libvips";
          repo = "libvips";
          rev = "v8.18.7";
          hash = "sha256-veceg2RJ0IXZ7zt/Bn9eJgTrpSghwz7+ogrmBT91Odk=";
        };
      });
  # Node 26.12.0 already includes <limits.h> in V8's memcopy.h. Keep its
  # substitute-compatible derivation; older consumers may need the backport.
  # https://github.com/nodejs/node/blob/v26.12.0/deps/v8/src/base/memcopy.h
  hasUpstreamArmFix =
    lib.versionAtLeast nodejs-slim_26.version "26.12.0"
    || lib.any (patch: lib.hasSuffix "/memcpy-climits.patch" (toString patch)) (
      nodejs-slim_26.patches or [ ]
    );
  nodejs =
    if stdenv.hostPlatform.isAarch64 && !hasUpstreamArmFix then
      nodejs_26.override {
        nodejs-slim = nodejs-slim_26.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + (builtins.readFile ./scripts/patch-node-v8-headers.sh);
        });
      }
    else
      nodejs_26;
  yarn = "${nodejs}/bin/node $(find .yarn/releases -maxdepth 1 -name 'yarn-*.cjs' -print -quit)";
in
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
    currentVips
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

  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  nativeInstallCheckInputs = [ nodejs ];
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        nodeModulesCheck = "${./scripts/check_node_modules.mts}";
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
