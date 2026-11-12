{
  replaceVars,
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  python3,
  installFonts,
}:
let
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation {
  pname = "craft-fonts";
  inherit (source) version;
  src = fetchFromGitHub {
    owner = "storytold";
    repo = "craft-fonts";
    inherit (source) rev hash;
  };
  strictDeps = true;
  nativeBuildInputs = [
    python3
    installFonts
  ];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    source ${
      replaceVars ./scripts/check-phase.sh {
        check_fonts_py = "${./check_fonts.py}";
      }
    }
  '';
  installPhase = builtins.readFile ./scripts/install-phase.sh;
  meta = {
    description = "Multilingual font collection used by the ArtCraft creative applications";
    homepage = "https://github.com/storytold/craft-fonts";
    maintainers = [
      {
        # Keep public attribution stable across Nixpkgs maintainer registries.
        github = "IanHollow";
        githubId = 72767437;
        name = "IanHollow";
      }
    ];
    license =
      with lib.licenses;
      AND [
        (OR [
          mit
          asl20
        ])
        ofl
      ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode
    ];
    platforms = lib.platforms.all;
  };
}
