# Check isolated packages first, then verify registry coverage and overlay evaluation.
{
  nixpkgs,
  system,
  overlay,
}:
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
  registeredNames = builtins.attrNames registered;
  overrides = overlay null base;
  overlaid = base.extend overlay;
  report = lib.concatMap inspect directories;
  supportedNames = map (entry: entry.name) report;
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
    assert lib.assertMsg (package ? override) "Missing override interface: ${entry.name}";
    # Discovery must read metadata for every package, even on unsupported hosts.
    # Only supported packages may force platform-specific dependencies and sources.
    if lib.meta.availableOn base.stdenv.hostPlatform package then
      assert lib.assertMsg (package.strictDeps or false) "Missing strictDeps: ${entry.name}";
      [
        {
          inherit (entry) name;
          inherit (package) drvPath;
          inherit (metadata)
            description
            homepage
            license
            platforms
            ;
        }
      ]
    else
      [ ];
in
assert lib.assertMsg
  (lib.sort builtins.lessThan names == lib.sort builtins.lessThan registeredNames)
  "Every package directory must have a registered public output, and every output its own directory";
assert lib.assertMsg (
  builtins.attrNames overrides == lib.sort builtins.lessThan supportedNames
) "Overlay names must match package platform metadata without unsupported overrides";
# Force actual overlay dependencies too, so eager filtering cannot introduce a
# fixed-point recursion that ordinary standalone package evaluation would miss.
builtins.deepSeq (map (name: overlaid.${name}.drvPath) supportedNames) report
