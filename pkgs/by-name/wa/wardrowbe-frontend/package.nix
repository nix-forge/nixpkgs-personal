{
  callPackage,
  replaceVars,
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  inter,
  nodejs_24,
  makeWrapper,
}:
let
  source = import ./source.nix;
in
buildNpmPackage (finalAttrs: {
  pname = "wardrowbe-frontend";
  inherit (source) version npmDepsHash;

  src = fetchFromGitHub {
    owner = "Anyesh";
    repo = "wardrowbe";
    inherit (source) rev;
    inherit (source) hash;
  };
  patches = [
    ./model-selection.patch
    ./oidc-token-auth-method.patch
    ./planning.patch
    ./outfit-browsing.patch
  ];
  sourceRoot = "source/frontend";
  nodejs = nodejs_24;
  npmFlags = [
    "--include=optional"
    "--legacy-peer-deps"
  ];
  env.NEXT_TELEMETRY_DISABLED = "1";
  strictDeps = true;
  nativeBuildInputs = [ makeWrapper ];

  postPatch = ''
    source ${replaceVars ./scripts/post-patch.sh { inherit inter; }}
  '';

  preBuild = builtins.readFile ./scripts/pre-build.sh;

  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        inter_src = inter.src;
        inherit nodejs_24;
      }
    }
  '';

  doInstallCheck = true;
  installCheckPhase = builtins.readFile ./scripts/install-check-phase.sh;

  passthru.updateScript = [
    (lib.getExe (callPackage ./update.nix { }))
    "--source-directory"
    (builtins.unsafeDiscardStringContext (toString ./.))
  ];
  meta = {
    description = "Wardrowbe wardrobe planner web frontend";
    homepage = "https://github.com/Anyesh/wardrowbe";
    changelog = "https://github.com/Anyesh/wardrowbe/releases/tag/wardrowbe-v${finalAttrs.version}";
    license = [
      lib.licenses.mit
      lib.licenses.ofl
    ];
    sourceProvenance = [
      lib.sourceTypes.fromSource
      lib.sourceTypes.binaryBytecode
    ];
    mainProgram = "wardrowbe-frontend";
    platforms = lib.platforms.linux;
  };
})
