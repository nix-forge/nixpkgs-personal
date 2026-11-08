{ nixpkgs, sourceFile }:
let
  pkgs = import nixpkgs { };
  source = import sourceFile;
  candidate = pkgs.codex.overrideAttrs {
    inherit (source) version cargoHash;
    buildCommit = source.rev;
    src = pkgs.fetchFromGitHub {
      owner = "openai";
      repo = "codex";
      inherit (source) rev hash;
    };
  };
in
candidate.cargoDeps
