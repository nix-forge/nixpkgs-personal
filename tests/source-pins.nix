{ pkgs }:
let
  inherit (pkgs) lib;
  byName = ../pkgs/by-name;
  validatorSource = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./check_source_pins.py
      ./check_artcraft_patch_lifecycle.py
      ./test_artcraft_patch_lifecycle.py
      ./test_source_release_metadata.py
    ];
  };
  artcraftNames = (import ../flake/artcraft-apps.nix) ++ [ "craft-fonts" ];
  lifecycleRegistry = ../docs/artcraft-patch-lifecycle.json;
  actualPatchInventory =
    assert lib.assertMsg (
      builtins.length artcraftNames == builtins.length (lib.unique artcraftNames)
    ) "The authoritative ArtCraft app list must not contain duplicate names";
    lib.genAttrs artcraftNames (
      name:
      let
        directory = byName + "/${builtins.substring 0 2 name}/${name}";
        entries = builtins.readDir directory;
        patches = builtins.filter (file: lib.hasSuffix ".patch" file) (builtins.attrNames entries);
      in
      lib.genAttrs patches (file: builtins.hashFile "sha256" (directory + "/${file}"))
    );
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
    actualPatches = builtins.toJSON actualPatchInventory;
    passAsFile = [
      "specification"
      "actualPatches"
    ];
  }
  ''
    python3 -B ${validatorSource}/test_source_release_metadata.py
    python3 -B ${validatorSource}/check_source_pins.py "$specificationPath"
    python3 -B ${validatorSource}/test_artcraft_patch_lifecycle.py
    python3 -B ${validatorSource}/check_artcraft_patch_lifecycle.py \
      ${lifecycleRegistry} "$specificationPath" "$actualPatchesPath"
    touch "$out"
  ''
