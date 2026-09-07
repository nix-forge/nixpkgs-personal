{
  perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      # Legacy fonts check the original bytes and sample color coverage. The
      # compiled Mutant font checks every source encoding through HarfBuzz.
      checks = {
        inherit (config.packages) emojione-legacy firefox-emoji mutant-standard-emoji;
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        inherit (config.packages) apple-color-emoji;
      };
    };
}
