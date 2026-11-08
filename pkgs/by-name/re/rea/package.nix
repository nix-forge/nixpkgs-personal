{
  lib,
  stdenv,
  clangStdenv,
  brotli,
  buildPackages,
  buildNpmPackage,
  fetchFromGitHub,
  fetchurl,
  nodejs_24,
  nodejs-slim_24,
  python3,
  bash,
  callPackage,
  replaceVars,
  testers,
  procps,
}:
let
  source = import ./source.nix;
  # Keep this security minimum local to REA rather than changing all packages.
  withReaNodeSource =
    compiler: scopedCallPackage: scopedBrotli: node:
    (node.override {
      stdenv = compiler;
      callPackage =
        path: args:
        scopedCallPackage path (
          args
          // {
            # Preserve version-specific Darwin toolchains selected by Nixpkgs.
            stdenv = if compiler.hostPlatform.isLinux then compiler else args.stdenv or compiler;
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
      (
        old:
        {
          inherit (source.nodejs) version;
          src = fetchurl {
            url = "https://nodejs.org/dist/v${source.nodejs.version}/node-v${source.nodejs.version}.tar.xz";
            inherit (source.nodejs) hash;
          };
        }
        // lib.optionalAttrs compiler.hostPlatform.isDarwin {
          patches = (old.patches or [ ]) ++ [
            ./node-darwin-tests.patch
            ./node-darwin-rss.patch
          ];
          preCheck = (old.preCheck or "") + ''
            # Match the test runner to the allocation, retaining compiler parallelism.
            export JOBS="$NIX_BUILD_CORES"
          '';
        }
      );
  # Keep eight compiler workers; Clang avoids the observed Linux GCC reclaim stall.
  targetCompiler = if stdenv.hostPlatform.isLinux then clangStdenv else stdenv;
  buildCompiler =
    if stdenv.buildPlatform.isLinux then buildPackages.clangStdenv else buildPackages.stdenv;
  # Override the compiled slim input, preserving Nixpkgs' Node patches and tests.
  targetNodejs = nodejs_24.override {
    nodejs-slim = withReaNodeSource targetCompiler callPackage brotli nodejs-slim_24;
  };
  buildNodejs = buildPackages.nodejs_24.override {
    nodejs-slim =
      withReaNodeSource buildCompiler buildPackages.callPackage buildPackages.brotli
        buildPackages.nodejs-slim_24;
  };
  targetNpmHooks = buildPackages.npmHooks.override { nodejs = targetNodejs; };
  appSrc = fetchFromGitHub {
    owner = "morluto";
    repo = "rea";
    inherit (source) rev hash;
  };
  darwinHelpers = callPackage ./darwin-helpers.nix { src = appSrc; };
  # @lydell/node-pty distributes platform binaries separately from its JS loader.
  # Compile its matching fork, not the different Microsoft 1.1.0 release.
  nodePty = stdenv.mkDerivation {
    pname = "rea-node-pty";
    inherit (source.nodePty) version;
    src = fetchFromGitHub {
      owner = "lydell";
      repo = "node-pty";
      inherit (source.nodePty) rev hash;
    };
    nodeAddonApi = fetchurl {
      url = "https://registry.npmjs.org/node-addon-api/-/node-addon-api-${source.nodeAddonApi.version}.tgz";
      inherit (source.nodeAddonApi) hash;
    };
    nativeBuildInputs = [
      buildNodejs
      (buildPackages.node-gyp.override { nodejs = buildNodejs; })
      python3
    ];
    strictDeps = true;
    configurePhase = ''
      runHook preConfigure
      mkdir -p node_modules/node-addon-api
      tar -xf "$nodeAddonApi" -C node_modules/node-addon-api --strip-components=1
      node -e 'if (JSON.parse(require("fs").readFileSync("package.json")).forkVersion !== process.argv[1]) process.exit(1)' '${source.nodePty.version}'
      runHook postConfigure
    '';
    buildPhase = ''
      runHook preBuild
      # Node-API headers are architecture independent. The target compiler and
      # explicit architecture compile the addon without executing target Node.
      node-gyp rebuild --nodedir=${buildNodejs} --arch=${stdenv.hostPlatform.node.arch}
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 build/Release/pty.node "$out/pty.node"
      ${lib.optionalString stdenv.hostPlatform.isDarwin ''
        install -Dm755 build/Release/spawn-helper "$out/spawn-helper"
      ''}
      install -Dm644 LICENSE "$out/share/licenses/rea-node-pty/LICENSE"
      install -Dm644 node_modules/node-addon-api/LICENSE.md "$out/share/licenses/node-addon-api/LICENSE.md"
      runHook postInstall
    '';
    meta.license = lib.licenses.mit;
  };
in
buildNpmPackage (finalAttrs: {
  pname = "rea";
  inherit (source) version npmDepsHash;
  src = appSrc;
  # Both core process ownership and optional native UI observations otherwise
  # compile Swift through /usr/bin/xcrun at runtime.
  patches = [ ./prebuilt-darwin-helpers.patch ];
  patchFlags = [
    "-p1"
    "--fuzz=0"
  ];
  # Build with executable build-platform Node; installed wrappers use target Node.
  nodejs = buildNodejs;
  buildInputs = [ targetNodejs ];
  inherit (targetNpmHooks) npmInstallHook;
  strictDeps = true;
  outputs = [
    "out"
    "skills"
  ];
  HUSKY = "0";
  TURBO_TELEMETRY_DISABLED = "1";
  # Lifecycle scripts are unnecessary. Compile with the explicit build task;
  # npm pack must not rerun prepack after development dependencies are pruned.
  npmFlags = [ "--ignore-scripts" ];
  npmPackFlags = [ "--ignore-scripts" ];
  # Process ownership needs ps even for static analysis workers. Other analysis
  # providers remain caller-selected and are not added to the closure.
  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (if stdenv.hostPlatform.isLinux then lib.makeBinPath [ procps ] else "/bin:/usr/bin")
  ];
  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  checkPhase = ''
    runHook preCheck
    npm exec -- vitest run --project domain --maxWorkers=2
    node scripts/generate-skill-metadata.mjs --check
    runHook postCheck
  '';
  postConfigure = ''
    source ${
      replaceVars ./scripts/post-configure.sh {
        inherit nodePty;
        # The locked Rust TypeScript compiler is a build-only npm prebuild.
        # Keep upstream's compiler identity and executable; fix its Linux loader.
        tsrsPatch = lib.optionalString stdenv.buildPlatform.isLinux ''
          tsrs="node_modules/@tsrs/linux-${stdenv.buildPlatform.node.arch}-gnu/tsrs"
          test -x "$tsrs"
          ${lib.getExe buildPackages.patchelf} \
            --set-interpreter ${buildPackages.stdenv.cc.bintools.dynamicLinker} \
            --add-rpath ${
              lib.makeLibraryPath [
                buildPackages.stdenv.cc.cc.lib
                buildPackages.glibc
              ]
            } \
            "$tsrs"
        '';
        ptyVersion = source.nodePty.version;
        ptyPackage = "@lydell/node-pty-${stdenv.hostPlatform.node.platform}-${stdenv.hostPlatform.node.arch}";
      }
    }
  '';
  postInstall = ''
    source ${replaceVars ./scripts/post-install.sh { }}
    mkdir -p "$out/share/licenses"
    cp -R ${nodePty}/share/licenses/. "$out/share/licenses/"
    # Keep Frida types through compilation and domain tests. Its optional native
    # provider is not built by this recipe; preserve every other optional package
    # (including the required platform PTY package).
    rm -rf "$out/lib/node_modules/rea-agents/node_modules/frida"
    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      install -m755 ${darwinHelpers}/bin/rea-process-token-reader "$out/lib/node_modules/rea-agents/bridge/process/rea-process-token-reader"
      install -m755 ${darwinHelpers}/bin/rea-native-ui "$out/lib/node_modules/rea-agents/bridge/native/rea-native-ui"
    ''}
  '';
  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  installCheckPhase = ''
    runHook preInstallCheck
    ${lib.getExe targetNodejs} ${./scripts/check-install.mts} \
      "$out" "$skills" '${finalAttrs.version}' ${lib.getExe bash} --sandbox
    runHook postInstallCheck
  '';
  passthru = {
    nativeAddon = nodePty;
    updateScript = [
      (lib.getExe (callPackage ./update.nix { }))
      "--source-directory"
      (builtins.unsafeDiscardStringContext (toString ./.))
    ];
    tests.version = testers.testVersion { package = finalAttrs.finalPackage; };
  };
  meta = {
    description = "Reverse engineering CLI and MCP server for native and packaged applications";
    homepage = "https://github.com/morluto/rea";
    changelog = "https://github.com/morluto/rea/releases/tag/rea-agents-${finalAttrs.version}";
    license = lib.licenses.mit;
    # EVMole is the unchanged locked npm dependency and includes WASM bytecode.
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
    mainProgram = "rea";
    outputsToInstall = [ "out" ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
})
