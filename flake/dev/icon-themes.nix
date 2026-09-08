{
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        inherit (config.packages) noctalia-dark-app-icons noctalia-personal;
      };
    };
}
