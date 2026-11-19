{ pkgs }:
let
  inherit (pkgs) lib;
  byName = ../../pkgs/by-name;
  sources = lib.concatMap (
    prefix:
    lib.concatMap (
      name:
      let
        directory = byName + "/${prefix}/${name}";
      in
      lib.optional (builtins.pathExists (directory + "/source.nix")) {
        inherit name;
        pins = import (directory + "/source.nix");
      }
    ) (builtins.attrNames (builtins.readDir (byName + "/${prefix}")))
  ) (builtins.attrNames (builtins.readDir byName));
in
pkgs.runCommand "source-pins"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    specification = builtins.toJSON sources;
    passAsFile = [ "specification" ];
  }
  ''
    python3 -B ${../../scripts/check_source_pins.py} "$specificationPath"
    python3 -B ${../../scripts/check_artcraft_patch_lifecycle.py} \
      "$specificationPath" ${../../docs/artcraft-patch-lifecycle.json} ${byName}
    touch "$out"
  ''
