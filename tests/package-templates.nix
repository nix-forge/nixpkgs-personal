# Build the real package hook templates without compiling their applications.
{
  pkgs,
  nixpkgs,
  system,
}:
let
  inherit (pkgs) lib;
  base = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
  # Generated validation text is materialized during evaluation. Preserve only
  # its existing source paths, never foreign application/toolchain derivations.
  isTemplate = path: builtins.match ".*\\.(sh|sh\\.in|py)" path != null;
  scope = base // {
    replaceVars = import ./package-template-renderer.nix { inherit lib; };
    callPackage = lib.callPackageWith scope;
  };
  packages = lib.filterAttrs (_: lib.meta.availableOn base.stdenv.hostPlatform) (
    import ../pkgs { pkgs = scope; }
  );
  hookText =
    package:
    let
      # Some passthru testers return a bare derivation without mkDerivation's
      # drvAttrs convenience attribute. Inspect its exported attributes instead.
      attrs = package.drvAttrs or package;
      names = lib.filter (
        name:
        name == "buildCommand"
        || lib.hasSuffix "Phase" name
        || lib.hasPrefix "pre" name
        || lib.hasPrefix "post" name
      ) (builtins.attrNames attrs);
    in
    lib.concatStringsSep "\n" (lib.filter builtins.isString (map (name: attrs.${name}) names));
  sources =
    package:
    let
      text = hookText package;
      context = lib.filterAttrs (path: _: isTemplate path) (builtins.getContext text);
      matches = lib.filter builtins.isList (
        builtins.split "source (/nix/store/[a-z0-9]{32}-[^ \n]+\\.sh)" text
      );
    in
    map (
      match: builtins.appendContext (builtins.unsafeDiscardStringContext (builtins.head match)) context
    ) matches;
  recipes =
    lib.concatMap (
      package: [ package ] ++ lib.collect lib.isDerivation (package.passthru.tests or { })
    ) (builtins.attrValues packages)
    # These package-local build stages are not public outputs or passthru tests.
    # Inspect their hooks explicitly without building models, fonts or Flutter.
    ++ lib.optionals (packages ? audiomuse-ai) [
      packages.audiomuse-ai.models
      (lib.findFirst (package: lib.getName package == "transformers")
        (throw "AudioMuse's composed Python environment must contain Transformers")
        packages.audiomuse-ai.pythonEnvironment.paths
      )
    ]
    ++ lib.optionals (packages ? mutant-standard-emoji) [ packages.mutant-standard-emoji.compiledFont ]
    ++ lib.optionals (packages ? apple-fonts) packages.apple-fonts.paths
    ++ lib.optionals (packages ? navidrome-plugin-audiomuseai-personal) [
      packages.navidrome-plugin-audiomuseai-personal.wasmSource
    ]
    ++ lib.optionals (packages ? pdfcraft) [ packages.pdfcraft.drvAttrs.PDFCRAFT_MODELS ]
    ++ lib.optionals (packages ? pdfcraft && base.stdenv.hostPlatform.isLinux) [
      packages.pdfcraft.tests.waylandClipboard.artifact
    ]
    ++ lib.optionals (packages ? jellyfin-plugin-moonbase) [
      (scope.callPackage ../pkgs/by-name/je/jellyfin-plugin-moonbase/web.nix { })
    ];
  scripts = lib.unique (lib.concatMap sources recipes);
  templates = pkgs.linkFarm "package-hook-templates-${system}" (
    map (script: {
      name = baseNameOf (builtins.unsafeDiscardStringContext script);
      path = script;
    }) scripts
  );
in
assert lib.assertMsg (scripts != [ ]) "No native package hook templates discovered";
pkgs.runCommand "package-templates-${system}" {
  nativeBuildInputs = [
    pkgs.bash
    pkgs.python3
  ];
  # Include nested sourced fragments and generated Python/launcher dependencies.
  exportReferencesGraph = [
    "template-closure"
    templates
  ];
} (builtins.readFile ./scripts/check-package-templates.sh)
