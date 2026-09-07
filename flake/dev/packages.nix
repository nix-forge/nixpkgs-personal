{ inputs, ... }: {
  perSystem = { pkgs, system, ... }: {
    checks.package-unit-tests =
      pkgs.runCommand "package-unit-tests"
        {
          nativeBuildInputs = [
            (pkgs.python3.withPackages (p: [ p.fonttools ]))
            pkgs.fontconfig
          ];
        }
        ''
          export FONT_FIXTURE=${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf
          export FONTCONFIG_FILE=${../../pkgs/by-name/ap/apple-fonts/fonts.conf}
          export XDG_CACHE_HOME="$TMPDIR/cache"
          python3 ${../../tests/run-package-tests.py} ${../..}
          touch "$out"
        '';
    checks.package-independence =
      let
        report = import ../../tests/package-contract.nix {
          inherit (inputs) nixpkgs;
          inherit system;
        };
      in
      # Force all metadata and derivation paths during evaluation on every system.
      builtins.deepSeq report (
        pkgs.runCommand "package-independence"
          {
            nativeBuildInputs = [ pkgs.python3 ];
            report = builtins.unsafeDiscardStringContext (builtins.toJSON report);
            passAsFile = [ "report" ];
          }
          ''
            python3 ${../../tests/check-package-layout.py} ${../..}
            python3 -B ${../..}/tests/test_package_layout.py
            cp "$reportPath" "$out"
          ''
      );
  };
}
