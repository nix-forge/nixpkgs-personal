{ pkgs }:
let
  inherit (pkgs) lib;
  # Preserve build/host dependency variants while resolving runtime arguments
  # against the incoming scope. Overlay newScope closes over final instead.
  scope =
    pkgs.splicePackages {
      inherit (pkgs)
        pkgsBuildBuild
        pkgsBuildHost
        pkgsBuildTarget
        pkgsHostHost
        pkgsTargetTarget
        ;
      pkgsHostTarget = pkgs;
    }
    // {
      # Nixpkgs keeps these package-set arguments outside dependency splicing.
      inherit (pkgs)
        pkgsBuildBuild
        pkgsBuildHost
        pkgsBuildTarget
        pkgsHostHost
        pkgsHostTarget
        pkgsTargetTarget
        buildPackages
        pkgs
        targetPackages
        ;
    };
  # Keep nested callPackage calls in the same upstream scope. In an overlay,
  # prev.callPackage otherwise closes over final and can inject personal packages.
  callPackage = lib.callPackageWith (scope // { inherit callPackage; });
  packagesByPrefix = lib.packagesFromDirectoryRecursive {
    inherit callPackage;
    directory = ./by-name;
  };
in
# Flatten prefix directories without forcing package values.
lib.mergeAttrsList (builtins.attrValues packagesByPrefix)
