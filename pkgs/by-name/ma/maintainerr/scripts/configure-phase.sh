# shellcheck shell=bash
runHook preConfigure
cmp yarn.lock @offlineCache@/yarn.lock
export HOME="$TMPDIR/yarn-home"
mkdir -p "$HOME" .yarn/cache
cp -R @offlineCache@/cache/. .yarn/cache/
chmod -R u+w .yarn/cache
export npm_config_nodedir=@srcOnly_nodejs@
export npm_config_node_gyp=@nodejs@/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js
@yarn@ install --immutable --inline-builds
(
  cd node_modules/better-sqlite3 || exit
  rm -rf build
  node ../node-gyp/bin/node-gyp.js rebuild --release --force_build=1
)
mkdir -p "$TMPDIR/build-tools"
makeWrapper @nodejs@/bin/node "$TMPDIR/build-tools/node-gyp" \
  --add-flags "$PWD/node_modules/node-gyp/bin/node-gyp.js"
(
  cd node_modules/sharp || exit
  PATH="$TMPDIR/build-tools:$PATH" \
    SHARP_FORCE_GLOBAL_LIBVIPS=1 node install/build.js
)
runHook postConfigure
