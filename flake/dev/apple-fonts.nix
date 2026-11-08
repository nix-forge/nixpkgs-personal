_: {
  perSystem =
    { pkgs, ... }:
    let
      fixture =
        name: content: (pkgs.writeTextDir "share/fonts/test.ttf" content).overrideAttrs { inherit name; };
      aggregate =
        paths:
        pkgs.callPackage ../../pkgs/by-name/ap/apple-fonts/package.nix {
          buildEnv =
            args:
            pkgs.buildEnv (
              args
              // {
                inherit paths;
                # This derivation contains only synthetic text fixtures, no vendor fonts.
                meta.license = pkgs.lib.licenses.mit;
              }
            );
        };
      first = fixture "first" "font fixture";
      same = fixture "same" "font fixture";
      different = fixture "different" "different font fixture";
    in
    {
      checks.apple-font-identical-collision = aggregate [
        first
        same
      ];
      checks.apple-font-conflicting-collision = pkgs.testers.testBuildFailure (aggregate [
        first
        different
      ]);
      devShells.apple-fonts = pkgs.mkShellNoCC {
        packages = [
          pkgs.python3
          pkgs.fontconfig
          pkgs._7zz
        ];
      };
      checks.apple-font-tooling =
        pkgs.runCommand "apple-font-tooling-tests"
          {
            nativeBuildInputs = [
              (pkgs.python3.withPackages (p: [ p.fonttools ]))
              pkgs.fontconfig
            ];
          }
          (
            (import ../../lib/render-text.nix) ./scripts/apple-font-tooling-tests.sh {
              pkgs_dejavu_fonts = pkgs.dejavu_fonts;
              pkgs_by_name_ap_apple_fonts_fonts_conf = ../../pkgs/by-name/ap/apple-fonts/fonts.conf;
              pkgs_lib_fileset_toSource_root_fileset_pkgs_lib_fileset_union = pkgs.lib.fileset.toSource {
                root = ../..;
                fileset = pkgs.lib.fileset.unions [
                  ../../pkgs/by-name/ap/apple-fonts
                  ../../pkgs/by-name/ap/apple-color-emoji
                  ../../pkgs/by-name/tt/ttf-ms-win11-auto
                ];
              };
            }
          );
    };
}
