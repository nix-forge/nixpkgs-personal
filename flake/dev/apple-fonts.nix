{
  perSystem = { pkgs, ... }: {
    devShells.apple-fonts = pkgs.mkShellNoCC {
      packages = [
        pkgs.python3
        pkgs.fontconfig
        pkgs._7zz
      ];
    };
  };
}
