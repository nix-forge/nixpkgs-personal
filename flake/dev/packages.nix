{
  lib,
  packageNixpkgs,
  packageOverlay,
  ...
}:
let
  unitSource = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.unions [
      ../../tests/run-package-tests.py
      ../../pkgs/by-name
    ];
  };
in
{
  perSystem = { pkgs, system, ... }: {
    checks.package-policy =
      let
        report = import ../../tests/package-policy.nix {
          nixpkgs = packageNixpkgs;
          overlay = packageOverlay;
          inherit system;
        };
      in
      builtins.deepSeq report (pkgs.writeText "package-policy.json" (builtins.toJSON report));
    checks.package-unit-tests =
      pkgs.runCommand "package-unit-tests"
        {
          nativeBuildInputs = [
            (pkgs.python3.withPackages (p: [
              p.fonttools
              p.pyyaml
            ]))
            pkgs.fontconfig
            pkgs.nodejs_24
            pkgs.pnpm_11
          ];
        }
        ''
          export FONT_FIXTURE=${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf
          export FONTCONFIG_FILE=${../../pkgs/by-name/ap/apple-fonts/fonts.conf}
          export XDG_CACHE_HOME="$TMPDIR/cache"
          python3 ${unitSource}/tests/run-package-tests.py ${unitSource}
          touch "$out"
        '';
    checks.package-independence =
      let
        report = import ../../tests/package-contract.nix {
          nixpkgs = packageNixpkgs;
          overlay = packageOverlay;
          inherit system;
        };
      in
      # Force all metadata and derivation paths during evaluation on every system.
      builtins.deepSeq report (
        pkgs.runCommand "package-independence"
          {
            nativeBuildInputs = [ pkgs.python3 ];
            # Record paths without making every package a build dependency of this check.
            report = builtins.unsafeDiscardStringContext (builtins.toJSON report);
            passAsFile = [ "report" ];
          }
          ''
            python3 ${../../tests/check-package-layout.py} ${../..}
            python3 -B ${../..}/tests/test_package_layout.py
            python3 -B ${../..}/tests/test_nur_check.py
            cp "$reportPath" "$out"
          ''
      );
  };
}
