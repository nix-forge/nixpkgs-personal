{ pkgs }:
let
  inherit (pkgs) lib;
  # Keep nested callPackage calls in the same upstream scope. In an overlay,
  # prev.callPackage otherwise closes over final and can inject personal packages.
  callPackage = lib.callPackageWith (pkgs // { inherit callPackage; });
  packagesByPrefix = lib.packagesFromDirectoryRecursive {
    inherit callPackage;
    directory = ./by-name;
  };
in
# Flatten prefix directories without forcing package values.
lib.mergeAttrsList (builtins.attrValues packagesByPrefix)
