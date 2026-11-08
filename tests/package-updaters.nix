{ pkgs, nixpkgs }:
let
  native = import nixpkgs { system = pkgs.stdenv.buildPlatform.system; };
  inherit (native) lib;
  byName = ../pkgs/by-name;
  directories = lib.concatMap (
    prefix:
    map (name: byName + "/${prefix}/${name}") (
      builtins.attrNames (builtins.readDir (byName + "/${prefix}"))
    )
  ) (builtins.attrNames (builtins.readDir byName));
  updaters = builtins.filter (path: builtins.pathExists (path + "/update.py")) directories;
  entries = map (directory: {
    name = baseNameOf directory;
    source = builtins.path {
      path = directory;
      name = "updater-source-${baseNameOf directory}";
    };
    command = lib.getExe (native.callPackage (directory + "/update.nix") { });
  }) updaters;
  python = pkgs.python3.withPackages (_: [
    (pkgs.callPackage ../pkgs/by-name/no/notification-process/package.nix { })
  ]);
in
pkgs.runCommand "package-updaters"
  {
    nativeBuildInputs = [ python ];
    specification = builtins.toJSON entries;
    passAsFile = [ "specification" ];
  }
  ''
    python3 ${./check_updater_commands.py} "$specificationPath"
    touch "$out"
  ''
