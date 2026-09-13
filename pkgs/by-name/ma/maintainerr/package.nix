{
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
  yarn = "${nodejs_26}/bin/node .yarn/releases/yarn-4.17.1.cjs";
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
    nodejs_26
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
    grep -Fq '"version": "${finalAttrs.version}"' package.json
    grep -Fq '"node": ">=26.0.0"' package.json
    substituteInPlace apps/server/src/app/config/typeOrmConfig.ts \
      --replace-fail "/opt/app/apps/server/dist/database/migrations" \
        "$out/libexec/maintainerr/apps/server/dist/database/migrations"
    substituteInPlace apps/server/src/modules/logging/logs.module.ts \
      --replace-fail "? '/opt/data'" \
        "? (process.env.DATA_DIR?.trim() || '/opt/data')"
    substituteInPlace apps/server/src/modules/logging/logs.controller.ts \
      --replace-fail "? '/opt/data/logs'" \
        "? path.join(process.env.DATA_DIR?.trim() || '/opt/data', 'logs')"
    printf '%s\n' 'VITE_BASE_PATH=/__PATH_PREFIX__' >> apps/ui/.env
  '';

  configurePhase = ''
    runHook preConfigure
    cmp yarn.lock ${finalAttrs.offlineCache}/yarn.lock
    export HOME="$TMPDIR/yarn-home"
    mkdir -p "$HOME" .yarn/cache
    cp -R ${finalAttrs.offlineCache}/cache/. .yarn/cache/
    chmod -R u+w .yarn/cache
    export npm_config_nodedir=${srcOnly nodejs_26}
    export npm_config_node_gyp=${nodejs_26}/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js
    ${yarn} install --immutable --inline-builds
    (
      cd node_modules/better-sqlite3
      rm -rf build
      node ../node-gyp/bin/node-gyp.js rebuild --release --force_build=1
    )
    mkdir -p "$TMPDIR/build-tools"
    makeWrapper ${nodejs_26}/bin/node "$TMPDIR/build-tools/node-gyp" \
      --add-flags "$PWD/node_modules/node-gyp/bin/node-gyp.js"
    (
      cd node_modules/sharp
      PATH="$TMPDIR/build-tools:$PATH" \
        SHARP_FORCE_GLOBAL_LIBVIPS=1 node install/build.js
    )
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    ${yarn} turbo build
    YARN_ENABLE_SCRIPTS=false ${yarn} workspaces focus --all --production
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    app="$out/libexec/maintainerr"
    mkdir -p "$app/apps/server/dist" "$app/apps/server/node_modules" \
      "$app/packages/contracts" "$out/bin" "$out/share/doc/maintainerr"

    cp -R node_modules "$app/"
    cp -R apps/server/dist/. "$app/apps/server/dist/"
    cp apps/server/package.json "$app/apps/server/package.json"
    if [ -d apps/server/node_modules ]; then
      cp -R apps/server/node_modules/. "$app/apps/server/node_modules/"
    fi
    cp -R apps/ui/dist "$app/apps/server/dist/ui"
    cp -R apps/server/assets "$app/apps/server/dist/assets"
    cp -R packages/contracts/dist "$app/packages/contracts/dist"
    cp packages/contracts/package.json "$app/packages/contracts/package.json"
    if [ -d packages/contracts/node_modules ]; then
      cp -R packages/contracts/node_modules "$app/packages/contracts/node_modules"
    else
      mkdir "$app/packages/contracts/node_modules"
    fi

    # Retain only runtime artifacts from source-built native addons.
    rm -rf \
      "$app/node_modules/better-sqlite3/prebuilds" \
      "$app/node_modules/better-sqlite3/deps" \
      "$app/node_modules/better-sqlite3/src" \
      "$app/node_modules/better-sqlite3/build/Release/obj.target" \
      "$app/node_modules/better-sqlite3/build/Release/.deps" \
      "$app/node_modules/canvas/build/Release/obj.target" \
      "$app/node_modules/canvas/build/Release/.deps" \
      "$app/node_modules/sharp/src/build/Release/obj.target" \
      "$app/node_modules/sharp/src/build/Release/.deps" \
      "$app/node_modules/sharp/src/build/Release/node-addon-api"
    rm -f \
      "$app/node_modules/better-sqlite3/build/Release/sqlite3.a" \
      "$app/node_modules/better-sqlite3/build/Release/test_extension.node"
    find "$app/node_modules/@img" -mindepth 1 -maxdepth 1 -type d \
      -name 'sharp-*' -exec rm -rf -- {} +

    install -Dm755 docker/start.sh "$out/libexec/maintainerr/start.sh"
    substituteInPlace "$out/libexec/maintainerr/start.sh" \
      --replace-fail '#!/bin/sh' '#!${stdenv.shell}' \
      --replace-fail '/opt/app/apps/server' "$app/apps/server" \
      --replace-fail 'user the container runs as' 'service user'
    makeWrapper "$out/libexec/maintainerr/start.sh" "$out/bin/maintainerr" \
      --prefix PATH : ${
        lib.makeBinPath [
          nodejs_26
          coreutils
          findutils
          gnused
        ]
      }

    install -Dm644 LICENSE "$out/share/doc/maintainerr/LICENSE"
    runHook postInstall
  '';

  doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
  nativeInstallCheckInputs = [ nodejs_26 ];
  installCheckPhase = ''
    runHook preInstallCheck
    cd "$out/libexec/maintainerr/apps/server"
    node -e "require('better-sqlite3'); require('canvas'); require('sharp')"
    test -f dist/main.js
    test -f dist/ui/index.html
    test -d dist/assets/fonts
    runHook postInstallCheck
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
