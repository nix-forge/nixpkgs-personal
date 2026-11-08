_: {
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      mkdocs = pkgs.python3.withPackages (python: [ python.mkdocs ]);
      source = lib.fileset.toSource {
        root = ../..;
        fileset = lib.fileset.unions [
          ../../docs
          ../../site
        ];
      };
      documentationSite =
        pkgs.runCommand "nixpkgs-personal-documentation-site" { nativeBuildInputs = [ mkdocs ]; }
          (
            (import ../../lib/render-text.nix) ./scripts/nixpkgs-personal-documentation-site.sh {
              inherit source;
            }
          );
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") { documentation-site = documentationSite; };
      devShells.docs = pkgs.mkShellNoCC { packages = [ mkdocs ]; };
    };
}
