# Inspect actual recipe scopes without compiling either native or foreign Node.
{ nixpkgs, system }:
let
  pkgs = import nixpkgs { inherit system; };
  native = pkgs.callPackage ../pkgs/by-name/re/rea/package.nix { };
  minimum = import ../pkgs/by-name/re/rea/source.nix;
  expectedReuse =
    (
      pkgs.stdenv.hostPlatform.isLinux
      || (pkgs.stdenv.hostPlatform.isDarwin && pkgs.lib.versionAtLeast pkgs.nodejs_24.version "24.22.2")
    )
    && pkgs.lib.versions.major pkgs.nodejs_24.version == "24"
    && pkgs.lib.versionAtLeast pkgs.nodejs_24.version minimum.nodejs.version
    && pkgs.lib.versionAtLeast pkgs.brotli.version minimum.brotli.version;
  cross =
    if system == "x86_64-linux" then
      (import nixpkgs {
        localSystem = system;
        crossSystem.config = "aarch64-unknown-linux-gnu";
      }).callPackage
        ../pkgs/by-name/re/rea/package.nix
        { }
    else
      null;
in
assert native.buildNodejs.drvPath == native.runtimeNodejs.drvPath;
assert native.reuseUpstreamNode == expectedReuse;
assert !expectedReuse || native.runtimeNodejs.drvPath == pkgs.nodejs_24.drvPath;
assert pkgs.lib.versionAtLeast native.runtimeNodejs.version minimum.nodejs.version;
assert native.doCheck && native.doInstallCheck;
assert
  cross == null
  || (
    cross.buildNodejs.drvPath != cross.runtimeNodejs.drvPath
    && cross.buildNodejs.stdenv.hostPlatform.system == "x86_64-linux"
    && cross.runtimeNodejs.stdenv.hostPlatform.system == "aarch64-linux"
  );
{
  inherit system expectedReuse;
  buildNode = native.buildNodejs.drvPath;
  runtimeNode = native.runtimeNodejs.drvPath;
  upstreamNode = pkgs.nodejs_24.drvPath;
  nodeVersion = native.runtimeNodejs.version;
}
