# Evaluation is intentionally independent of the flake's overlay and registry scope.
{ nixpkgs, system }:
let
  base = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  inherit (base) lib;
  byName = ../pkgs/by-name;
  directories = lib.concatMap (
    prefix:
    map (name: {
      inherit name;
      path = byName + "/${prefix}/${name}";
    }) (builtins.attrNames (builtins.readDir (byName + "/${prefix}")))
  ) (builtins.attrNames (builtins.readDir byName));
  names = map (entry: entry.name) directories;
  # A personal dependency must fail even if Nixpkgs later adds the same name.
  scope =
    base
    // lib.genAttrs names (name: throw "Personal dependency is forbidden: ${name}")
    // {
      callPackage = lib.callPackageWith scope;
    };
  registered = import ../pkgs { pkgs = base; };
  supportedSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];
  registeredNames = lib.unique (
    lib.concatMap (
      target:
      builtins.attrNames (
        import ../pkgs {
          pkgs = import nixpkgs {
            system = target;
            config.allowUnfree = true;
          };
        }
      )
    ) supportedSystems
  );
  inspect =
    entry:
    let
      # Only this directory enters the store, so sibling filesystem imports fail.
      isolated = builtins.path {
        inherit (entry) path;
        name = "standalone-${entry.name}";
      };
      package = scope.callPackage (isolated + "/package.nix") { };
      metadata = package.meta;
    in
    assert lib.assertMsg (builtins.pathExists (
      entry.path + "/package.nix"
    )) "Missing package.nix: ${entry.name}";
    assert lib.assertMsg (lib.isDerivation package) "Not a derivation: ${entry.name}";
    assert lib.assertMsg (metadata.description or "" != "") "Missing description: ${entry.name}";
    assert lib.assertMsg (metadata.homepage or "" != "") "Missing homepage: ${entry.name}";
    assert lib.assertMsg (metadata ? license) "Missing license: ${entry.name}";
    assert lib.assertMsg (metadata.platforms or [ ] != [ ]) "Missing platforms: ${entry.name}";
    assert lib.assertMsg (lib.meta.availableOn base.stdenv.hostPlatform package)
      "Incorrect platform: ${entry.name}";
    assert lib.assertMsg (package.strictDeps or false) "Missing strictDeps: ${entry.name}";
    assert lib.assertMsg (package ? override) "Missing override interface: ${entry.name}";
    {
      inherit (entry) name;
      inherit (package) drvPath;
      inherit (metadata)
        description
        homepage
        license
        platforms
        ;
    };
in
assert lib.assertMsg
  (lib.sort builtins.lessThan names == lib.sort builtins.lessThan registeredNames)
  "Every package directory must have a registered public output, and every output its own directory";
map inspect (builtins.filter (entry: builtins.hasAttr entry.name registered) directories)
