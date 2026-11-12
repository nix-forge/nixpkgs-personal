# Check isolated packages first, then verify registry coverage and overlay evaluation.
{
  nixpkgs,
  system,
  overlay,
}:
let
  base = import nixpkgs {
    inherit system;
    config = {
      allowUnfree = true;
      checkMeta = true;
    };
  };
  inherit (base) lib;
  crossScopeValid = import ./package-cross-scope.nix { inherit nixpkgs system; };
  licenseMetadata = import ../scripts/license-metadata.nix;
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
  swiftRecipes = [
    registered.finder-favorites
    registered.ocr-capture
    registered.vorssaint
  ];
  hasNativeBuildInput =
    dependency: package:
    builtins.elem dependency.drvPath (map (input: input.drvPath) package.nativeBuildInputs);
  swiftInputsValid =
    if system != "aarch64-darwin" then
      true
    else
      builtins.all (hasNativeBuildInput base.swift) swiftRecipes
      && registered.finder-favorites.SWIFT_EXEC == "${base.swift}/bin/swiftc"
      &&
        (registered.finder-favorites.override {
          swift = base.swift.overrideAttrs (_: {
            name = "alternate-swift";
          });
        }).SWIFT_EXEC == "${
          base.swift.overrideAttrs (_: {
            name = "alternate-swift";
          })
        }/bin/swiftc"
      && hasNativeBuildInput base.swiftpm registered.finder-favorites
      && !(hasNativeBuildInput base.swiftpm registered.ocr-capture)
      && !(hasNativeBuildInput base.swiftpm registered.vorssaint);
  maintainerrNodeValid =
    if system == "aarch64-darwin" then
      true
    else
      hasNativeBuildInput base.nodejs_26 registered.maintainerr;
  maintainerrVipsValid =
    system == "aarch64-darwin"
    || lib.versionOlder base.vips.version "8.18.7"
    || builtins.elem base.vips.drvPath (map (input: input.drvPath) registered.maintainerr.buildInputs);
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
      # Standalone recipes carry their helper sources. Compare them with the
      # catalog copies so shared fixes cannot silently leave a recipe behind.
      helperSources = {
        "run_update.py" = ./run_update.py;
        "update_nix.py" = ./update_nix.py;
        "update_transaction.py" = ./update_transaction.py;
        "check_desktop_entry.py" = ./check_desktop_entry.py;
        "check_app_bundle.py" = ./check_app_bundle.py;
        "notification_process.py" = ../pkgs/by-name/no/notification-process/src/notification_process.py;
        "check_craft_assets.py" = ./check_craft_assets.py;
        "update_vendor_checksum.py" = ./update_vendor_checksum.py;
        "check_node_modules.mts" = ./check_node_modules.mts;
      };
      helpersCurrent = lib.all (
        name:
        let
          local =
            entry.path
            + (
              if
                builtins.elem name [
                  "notification_process.py"
                  "run_update.py"
                  "update_nix.py"
                  "update_transaction.py"
                ]
              then
                "/${name}"
              else
                "/scripts/${name}"
            );
        in
        !(builtins.pathExists local) || builtins.readFile local == builtins.readFile helperSources.${name}
      ) (builtins.attrNames helperSources);
    in
    assert lib.assertMsg (builtins.pathExists (
      entry.path + "/package.nix"
    )) "Missing package.nix: ${entry.name}";
    assert lib.assertMsg helpersCurrent "Stale standalone helper: ${entry.name}";
    assert lib.assertMsg (lib.isDerivation package) "Not a derivation: ${entry.name}";
    assert lib.assertMsg (metadata.description or "" != "") "Missing description: ${entry.name}";
    assert lib.assertMsg (metadata.homepage or "" != "") "Missing homepage: ${entry.name}";
    assert lib.assertMsg (
      !(metadata ? mainDarwinApp)
      || (
        base.stdenv.hostPlatform.isDarwin
        && lib.hasSuffix ".app" metadata.mainDarwinApp
        && !(lib.hasInfix "/" metadata.mainDarwinApp)
      )
    ) "Darwin application metadata must name a bundle on Darwin: ${entry.name}";
    assert lib.assertMsg (metadata ? license) "Missing license: ${entry.name}";
    assert lib.assertMsg (lib.all licenseMetadata.valid (
      lib.toList metadata.license
    )) "License must declare freedom explicitly, not use a string: ${entry.name}";
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
          mainProgram = metadata.mainProgram or null;
          mainDarwinApp = metadata.mainDarwinApp or null;
          maintainers = metadata.maintainers or [ ];
          sourceProvenance = metadata.sourceProvenance or [ ];
        }
      ]
    else
      [ ];
in
assert lib.assertMsg crossScopeValid
  "Cross packages must instantiate standalone, through the registry and through an overlay";
assert lib.assertMsg
  (lib.sort builtins.lessThan names == lib.sort builtins.lessThan registeredNames)
  "Every package directory must have a registered public output, and every output its own directory";
assert lib.assertMsg (
  builtins.attrNames overrides == lib.sort builtins.lessThan supportedNames
) "Overlay names must match package platform metadata without unsupported overrides";
assert lib.assertMsg swiftInputsValid
  "Swift packages must use the pinned compiler and SwiftPM only where needed";
assert lib.assertMsg maintainerrNodeValid
  "Maintainerr must use the pinned Nixpkgs Node.js 26 derivation";
assert lib.assertMsg maintainerrVipsValid
  "Maintainerr must use the unmodified Nixpkgs libvips when it meets sharp's minimum version";
# Force actual overlay dependencies too, so eager filtering cannot introduce a
# fixed-point recursion that ordinary standalone package evaluation would miss.
builtins.deepSeq (map (name: overlaid.${name}.drvPath) supportedNames) report
