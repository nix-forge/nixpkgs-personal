{
  replaceVars,
  lib,
  stdenv,
  fetchgit,
  fetchPnpmDeps,
  nodejs,
  pnpm_11,
  pnpmConfigHook,
  ffmpeg,
  makeWrapper,
  callPackage,
  python3,
}:
let
  source = import ./source.nix;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "bookorbit";
  inherit (source) version;
  __structuredAttrs = true;
  strictDeps = true;

  # Nix builders use a zero-width PTY; disable interactive compiler redraws.
  env.CI = "true";
  env.TERM = "dumb";

  src = fetchgit {
    url = "https://github.com/bookorbit/bookorbit.git";
    inherit (source) rev hash;
  };

  pnpmWorkspaces = [
    "client..."
    "server..."
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs)
      pname
      version
      src
      pnpmWorkspaces
      ;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    hash = source.pnpmHash;
  };

  nativeBuildInputs = [
    (callPackage ./swc-native-verifier.nix { })
    python3
    nodejs
    pnpm_11
    pnpmConfigHook
    ffmpeg
    makeWrapper
  ];

  preBuild = ''
    source ${
      replaceVars ./scripts/pre-build.sh {
        inherit nodejs;
        nativeTarget = stdenv.hostPlatform.rust.rustcTarget;
        nativePackage = "@swc/core-${stdenv.hostPlatform.parsed.kernel.name}-${
          if stdenv.hostPlatform.isAarch64 then "arm64" else "x64"
        }${
          lib.optionalString stdenv.hostPlatform.isLinux (
            if stdenv.hostPlatform.isMusl then "-musl" else "-gnu"
          )
        }";
        swc_native_verifier = callPackage ./swc-native-verifier.nix { };
        scripts_materialize_swc_py = ./scripts/materialize_swc.py;
        scripts_select_swc_cjs = ./scripts/select-swc.cjs;
      }
    }
  '';
  buildPhase = builtins.readFile ./scripts/build-phase.sh;

  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        inherit nodejs;
        inherit (finalAttrs) version;
      }
    }
  '';

  doInstallCheck = true;
  installCheckPhase = builtins.readFile ./scripts/install-check-phase.sh;

  meta = {
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    description = "Library management and reading platform";
    homepage = "https://github.com/bookorbit/bookorbit";
    changelog = "https://github.com/bookorbit/bookorbit/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "bookorbit";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
})
