{ pkgs }:
pkgs.buildNpmPackage {
  pname = "package-javascript-tools";
  version = "1";
  src = pkgs.lib.fileset.toSource {
    root = ../..;
    fileset = pkgs.lib.fileset.unions [
      ../../package.json
      ../../package-lock.json
    ];
  };
  nodejs = pkgs.nodejs_24;
  npmDepsHash = "sha256-qrTPr6ETHorMviVvpsqtp+aC2X7ALMyKA0ldDmfu4Uw=";
  dontNpmBuild = true;
  dontNpmInstall = true;
  nativeBuildInputs = [ pkgs.makeWrapper ];
  installPhase = (import ../../lib/render-text.nix) ./scripts/javascript-tools-install.sh.in {
    node = pkgs.lib.getExe pkgs.nodejs_24;
  };
  meta.mainProgram = "oxlint";
}
