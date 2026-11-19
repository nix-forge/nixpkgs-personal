{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_24,
}:
let
  source = import ./source.nix;
in
buildNpmPackage (_finalAttrs: {
  pname = "scrypted-plugin-arlo";
  inherit (source) version npmDepsHash;

  src = fetchFromGitHub {
    owner = "scryptedapp";
    repo = "arlo";
    inherit (source) rev;
    inherit (source) hash;
  };

  nodejs = nodejs_24;
  strictDeps = true;
  npmFlags = [ "--ignore-scripts" ];

  buildPhase = builtins.readFile ./scripts/build-phase.sh;

  installPhase = builtins.readFile ./scripts/install-phase.sh;

  meta = {
    description = "Arlo camera plugin for Scrypted";
    homepage = "https://github.com/scryptedapp/arlo";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
  };
})
