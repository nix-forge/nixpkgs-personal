{
  lib,
  stdenvNoCC,
  typescript,
}:
stdenvNoCC.mkDerivation {
  pname = "metabrainz-spicetify-extension";
  version = "1";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./metabrainz.ts
      ./tsconfig.json
    ];
  };

  strictDeps = true;
  nativeBuildInputs = [ typescript ];

  buildPhase = builtins.readFile ./scripts/build-phase.sh;

  installPhase = builtins.readFile ./scripts/install-phase.sh;

  meta = {
    description = "Spicetify context menu links to MetaBrainz search";
    homepage = "https://github.com/nix-forge/nixpkgs-personal/tree/main/pkgs/by-name/me/metabrainz-spicetify-extension";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
