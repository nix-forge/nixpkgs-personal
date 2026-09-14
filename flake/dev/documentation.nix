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
          ''
            cp -R ${source}/. source
            chmod -R u+w source
            mkdocs build --config-file source/site/mkdocs.yml --site-dir "$out" --strict
            test -s "$out/index.html"
            test -s "$out/search/search_index.json"
          '';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") { documentation-site = documentationSite; };
      devShells.docs = pkgs.mkShellNoCC { packages = [ mkdocs ]; };
    };
}
