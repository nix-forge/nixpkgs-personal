_: {
  perSystem = { pkgs, ... }: {
    checks.lib-tests =
      pkgs.runCommand "package-library-tests" { nativeBuildInputs = [ pkgs.nix-unit ]; }
        ''
          export HOME="$TMPDIR/home"
          mkdir -p "$HOME"
          nix-unit --eval-store "$TMPDIR/eval-store" --expr 'import ${../../lib}/tests { lib = import ${pkgs.path}/lib; }'
          touch "$out"
        '';
  };
}
