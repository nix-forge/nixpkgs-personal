{
  pnpm_12,
  nodejs,
  rustPlatform,
  buildGoModule,
  fetchFromGitHub,
  fetchurl,
}:

# Beta's workspace permissions require pnpm >= 12.11. Keep its pinned tool
# until Nixpkgs supplies a compatible version and native Beta checks pass.
let
  version = "12.14.0";
  cargoHash = "sha256-l0YjM2muWPzHvP/Stlv+10k3YFtGGPZmHjanqPOb2zU=";
  certificatePatches = [ ./pnpm-webpki.patch ];
  # Match the compiler and complete closure in pnpm 12.14's loader lockfile.
  loaderBundler = buildGoModule {
    pname = "esbuild";
    version = "0.28.2";
    src = fetchFromGitHub {
      owner = "evanw";
      repo = "esbuild";
      rev = "v0.28.2";
      hash = "sha256-I1u+9U5Oj/KzxSjCxwyitwSuDKimatkbC3R2OtaUsfM=";
    };
    # go.mod and go.sum are unchanged from Nixpkgs' esbuild 0.27.2.
    vendorHash = "sha256-+BfxCyg0KkDQpHt/wycy/8CTG6YBA/VJvJFhhzUnSiQ=";
    subPackages = [ "cmd/esbuild" ];
    ldflags = [
      "-s"
      "-w"
    ];
  };
  enhancedResolve = fetchurl {
    url = "https://registry.npmjs.org/enhanced-resolve/-/enhanced-resolve-5.26.0.tgz";
    hash = "sha512-9vhedylFonb2YGogzUKX6+Ja72gOJbN1QHAqdrvqLwhdl/QWbKopzoUC9EbQNVsAns/bx/4uyqalrQAoy1IByw==";
  };
  gracefulFs = fetchurl {
    url = "https://registry.npmjs.org/graceful-fs/-/graceful-fs-4.2.11.tgz";
    hash = "sha512-RbJ5/jmFcNNCcDV5o9eTnBLJ/HszWV0P73bc+Ff4nS/rJj+YaS6IGyiOL0VoBYX+l1Wrl3k63h/KrH+nhJ0XvQ==";
  };
  tapable = fetchurl {
    url = "https://registry.npmjs.org/tapable/-/tapable-2.3.3.tgz";
    hash = "sha512-uxc/zpqFg6x7C8vOE7lh6Lbda8eEL9zmVm/PLeTPBRhh1xCgdWaQ+J1CUieGpIfm2HdtsUpRv+HshiasBMcc6A==";
  };
  base = pnpm_12.override {
    inherit version cargoHash;
    srcHash = "sha256-tZHWmdPmCGWCju6WzpQDyZXjaGB7cePDJ7eUTwc0LsY=";
    nodejs-slim = nodejs;
  };
in
base.overrideAttrs (previousAttrs: {
  # Apply the certificate updates to both the build and vendor lockfiles.
  patches = certificatePatches;
  cargoDeps = rustPlatform.fetchCargoVendor {
    pname = "pnpm";
    inherit version;
    inherit (base) src;
    patches = certificatePatches;
    hash = cargoHash;
  };
  nativeBuildInputs = previousAttrs.nativeBuildInputs ++ [
    loaderBundler
    nodejs
  ];
  postPatch = (previousAttrs.postPatch or "") + ''
    mkdir -p node_modules/{enhanced-resolve,graceful-fs,tapable}
    tar -xf ${enhancedResolve} --strip-components=1 -C node_modules/enhanced-resolve
    tar -xf ${gracefulFs} --strip-components=1 -C node_modules/graceful-fs
    tar -xf ${tapable} --strip-components=1 -C node_modules/tapable
    patch --fuzz=0 -p1 -d node_modules/graceful-fs < __patches__/graceful-fs@4.2.11.patch

    test "$(esbuild --version)" = 0.28.2
    # Reproduce pnpm/esm-loader/scripts/bundle-runtime.mjs without installs.
    esbuild pnpm/esm-loader/install-register.mjs \
      --bundle --minify --platform=node --format=esm \
      --banner:js="import { createRequire as bootstrapRequire } from 'node:module'; const require = bootstrapRequire(import.meta.url);" \
      --outfile=pnpm/crates/deps-restorer/src/cas-loader.mjs.inc
    test -s pnpm/crates/deps-restorer/src/cas-loader.mjs.inc
    env -u FORCE_COLOR NO_COLOR=1 node --input-type=module --check < pnpm/crates/deps-restorer/src/cas-loader.mjs.inc
    env -u FORCE_COLOR NO_COLOR=1 node --test pnpm/esm-loader/test/loader.test.mjs
    env -u FORCE_COLOR NO_COLOR=1 node ${./pnpm-loader-check.mjs} "$PWD"
  '';
})
