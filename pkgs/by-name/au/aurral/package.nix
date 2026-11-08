{
  replaceVars,
  callPackage,
  lib,
  fetchPnpmDeps,
  pnpmConfigHook,
  buildPackages,
  fetchurl,
  nodejs-slim_26,
  node-gyp,
  fetchFromGitHub,
  nodejs_26,
  python3,
  pkg-config,
  autoPatchelfHook,
  stdenv,
  clangStdenv,
  brotli,
  vips,
  sqlite,
  makeWrapper,
  git,
  procps,
  ffmpeg,
  yt-dlp,
  fontconfig,
}:
let
  source = import ./source.nix;
  # Match Node 26's official Linux Clang toolchain. Eight GCC workers exceed
  # the reviewed daemon working set; keep compiler parallelism and optimization.
  withAurralNodeSource =
    compiler: scopedCallPackage: scopedBrotli: node:
    (node.override {
      stdenv = compiler;
      # The version wrapper calls its generic builder through this scope; merely
      # overriding the wrapper's stdenv changes patch selection, not compilation.
      callPackage =
        path: args:
        scopedCallPackage path (
          args
          // {
            stdenv = compiler;
            # Node 26.13 exposes the security-fixed decoder's BLOCK_SWITCH error.
            brotli = scopedBrotli.overrideAttrs (_: {
              inherit (source.brotli) version;
              src = fetchFromGitHub {
                owner = "google";
                repo = "brotli";
                tag = "v${source.brotli.version}";
                inherit (source.brotli) hash;
              };
            });
          }
        );
    }).overrideAttrs
      (_: {
        inherit (source.nodejs) version;
        src = fetchurl {
          url = "https://nodejs.org/dist/v${source.nodejs.version}/node-v${source.nodejs.version}.tar.xz";
          inherit (source.nodejs) hash;
        };
      });
  targetNodejsSlim = withAurralNodeSource clangStdenv callPackage brotli nodejs-slim_26;
  buildNodejsSlim =
    withAurralNodeSource buildPackages.clangStdenv buildPackages.callPackage buildPackages.brotli
      buildPackages.nodejs-slim_26;
  targetNodejs = nodejs_26.override { nodejs-slim = targetNodejsSlim; };
  buildNodejs = buildPackages.nodejs_26.override { nodejs-slim = buildNodejsSlim; };
  pnpm = buildPackages.callPackage ./pnpm.nix { nodejs = buildNodejs; };
  # Keep the typed API helper beside tests whose imports resolve relatively.
  testSource = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./test-api.mts
      ./lidarr-metadata.test.mts
      ./listenbrainz-discover.test.mts
      ./listenbrainz-connect.test.mts
      ./native-audio-tags.test.mts
      ./artist-identity.test.mts
      ./canonical-artwork.test.mts
      ./navidrome-managed-library.test.mts
      ./matcher-runtime.test.mts
    ];
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "aurral";
  inherit (source) version;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "lklynet";
    repo = "aurral";
    tag = "v${finalAttrs.version}";
    inherit (source) hash;
  };

  patches = [
    ./lidarr-metadata.patch
    ./listenbrainz-discover.patch
    ./listenbrainz-connect.patch
    ./native-audio-tags.patch
    ./artist-identity.patch
    ./canonical-artwork.patch
    ./navidrome-managed-library.patch
  ];

  # Every patch is reviewed against the exact source pin; reject stale context.
  patchFlags = [
    "-p1"
    "--fuzz=0"
  ];

  pnpmWorkspaces = [
    "aurral..."
    "aurral-backend..."
    "aurral-frontend..."
  ];
  pnpmDeps =
    assert buildNodejsSlim.stdenv.cc.isClang;
    assert targetNodejsSlim.stdenv.cc.isClang;
    fetchPnpmDeps {
      inherit (finalAttrs)
        pname
        version
        src
        patches
        postPatch
        pnpmWorkspaces
        ;
      inherit pnpm;
      fetcherVersion = 4;
      hash = source.pnpmHash;
      # pnpm 12's native CLI can use portable JSON package indexes instead of
      # SQLite. This avoids relying on the pnpm 11 state-database ABI.
      env.pnpm_config_store_index_format = "files";
      env.pnpm_config_force_ignores_platform = "true";
      nativeBuildInputs = [ buildNodejs ];
    };

  nativeBuildInputs = [
    python3
    buildNodejs
    pnpm
    pnpmConfigHook
    (node-gyp.override { nodejs = buildNodejs; })
    pkg-config
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    vips
    sqlite
  ];

  env = {
    # Sharp's source-build script requires node-gyp as a JS module as well as
    # invoking its CLI. Keep this build-only dependency outside the pnpm lock.
    NODE_PATH = lib.makeSearchPath "lib/node_modules" [ (node-gyp.override { nodejs = buildNodejs; }) ];
    npm_config_build_from_source = "true";
    npm_config_nodedir = "${buildNodejs}";
    pnpm_config_store_index_format = "files";
    pnpm_config_pm_on_fail = "ignore";
    CI = "true";
    SHARP_FORCE_GLOBAL_LIBVIPS = "1";
    VITE_APP_VERSION = finalAttrs.version;
    VITE_GITHUB_REPO = "lklynet/aurral";
    VITE_RELEASE_CHANNEL = "stable";
  };

  postPatch = builtins.readFile ./scripts/post-patch.sh;

  # pnpmConfigHook installs through postConfigureHooks, after the postConfigure
  # attribute. Rebuild the native addons only once that installation finishes.
  preBuild = builtins.readFile ./scripts/post-configure.sh;

  buildPhase = ''
    runHook preBuild
    pnpm --filter aurral-frontend run build
    runHook postBuild
  '';

  doCheck = true;
  nativeCheckInputs = [
    git
    ffmpeg
    procps
  ];
  checkPhase = ''
    runHook preCheck
    node scripts/typecheck.mts
    pnpm test --maxWorkers="$NIX_BUILD_CORES"
    runHook postCheck
  '';

  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        nodejs = targetNodejs;
        mediaToolsPath = lib.makeBinPath [
          ffmpeg
          yt-dlp
          fontconfig
        ];
        inherit (finalAttrs) version;
      }
    }
  '';

  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  nativeInstallCheckInputs = [
    buildNodejs
    ffmpeg
  ];
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        lidarr_metadata_test_mts = "${testSource}/lidarr-metadata.test.mts";
        listenbrainz_discover_test_mts = "${testSource}/listenbrainz-discover.test.mts";
        listenbrainz_connect_test_mts = "${testSource}/listenbrainz-connect.test.mts";
        native_audio_tags_test_mts = "${testSource}/native-audio-tags.test.mts";
        artist_identity_test_mts = "${testSource}/artist-identity.test.mts";
        canonical_artwork_test_mts = "${testSource}/canonical-artwork.test.mts";
        navidrome_managed_library_test_mts = "${testSource}/navidrome-managed-library.test.mts";
        matcher_runtime_test_mts = "${testSource}/matcher-runtime.test.mts";
        nativeCheck = "${./scripts/check-native.mts}";

      }
    }
  '';

  meta = {
    description = "Music discovery, requests, and library management web application";
    homepage = "https://aurral.org";
    changelog = "https://github.com/lklynet/aurral/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "aurral";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    # Honker retains npm native binaries. The application, frontend, and the
    # better-sqlite3, bcrypt, and sharp addons are built from source.
    sourceProvenance = [
      lib.sourceTypes.fromSource
      lib.sourceTypes.binaryNativeCode
    ];
  };
})
