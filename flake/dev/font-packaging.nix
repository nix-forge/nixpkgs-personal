{
  perSystem = { config, pkgs, ... }: {
    # Home Manager combines font files into one profile. Check the full design
    # catalog with its complementary M PLUS styles before building the desktop.
    checks.design-font-coexistence = pkgs.buildEnv {
      name = "design-font-coexistence";
      paths = with config.packages; [
        google-fonts-design
        mplus-outline-fonts-compatible
      ];
      pathsToLink = [ "/share/fonts" ];
    };
  };
}
