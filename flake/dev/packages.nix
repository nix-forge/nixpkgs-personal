{ lib, packageNixpkgs, ... }: {
  perSystem = { pkgs, system, ... }: {
    checks = {
      source-pins = import ./source-pins.nix { inherit pkgs; };
      package-templates = import ./package-templates.nix {
        inherit pkgs system;
        nixpkgs = packageNixpkgs;
      };
      javascript-quality = pkgs.stdenvNoCC.mkDerivation {
        pname = "package-javascript-quality";
        version = "1";
        src = lib.fileset.toSource {
          root = ../..;
          fileset = lib.fileset.unions [
            ../../.editorconfig
            ../../.oxlintrc.json
            ../../tsconfig.json
            ../../scripts/javascript
            (lib.fileset.fileFilter (
              file:
              builtins.any file.hasExt [
                "ts"
                "mts"
                "cts"
                "tsx"
                "js"
                "mjs"
                "cjs"
                "jsx"
              ]
              || builtins.elem file.name [
                "tsconfig.json"
                "application-types.json"
                ".oxlintrc.json"
              ]
            ) ../../pkgs/by-name)
          ];
        };
        nativeBuildInputs = [ (import ./javascript-tools.nix { inherit pkgs; }) ];
        dontConfigure = true;
        dontBuild = true;
        doCheck = true;
        checkPhase = builtins.readFile ./scripts/check-javascript.sh;
        installPhase = builtins.readFile ./scripts/install-check-output.sh;
      };
    };
  };
}
