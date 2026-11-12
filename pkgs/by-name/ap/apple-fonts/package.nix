{
  callPackage,
  replaceVars,
  lib,
  stdenvNoCC,
  fetchurl,
  requireFile,
  python3,
  fontconfig,
  _7zz,
  buildEnv,
  writeText,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./sources.json);
  licenseEvidence = builtins.fromJSON (builtins.readFile ./license-evidence.json);
  builder = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./unpack_font_distribution.py
      ./font_support.py
    ];
  };
  updateScript = [
    (lib.getExe (callPackage ./update.nix { }))
    "--source-directory"
    (builtins.unsafeDiscardStringContext (toString ./.))
  ];
  mkFont =
    entry: src:
    stdenvNoCC.mkDerivation {
      pname = entry.name;
      inherit (entry) version;
      inherit src;
      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;
      strictDeps = true;
      nativeBuildInputs = [
        python3
        fontconfig
        _7zz
      ];
      installPhase = ''
        source ${
          replaceVars ./scripts/install-phase.sh {
            fonts_conf = "${./fonts.conf}";
            inherit builder;
            fontManifest = writeText "font-manifest.json" (builtins.toJSON entry);
            readme = "${./README.md}";
            entry_name = entry.name;
            licenseScope = writeText "license-scope.json" (
              builtins.toJSON {
                source = entry.name;
                inherit (entry) hash;
                url = entry.url or null;
                evidence = licenseEvidence.sources.${entry.name} or licenseEvidence.default;
              }
            );
          }
        }
      '';
      # Verification in unpack_font_distribution.py checks the manifest, face identities and every
      # copied byte before this derivation succeeds.
      preferLocalBuild = true;
      allowSubstitutes = false;
      passthru = {
        inherit updateScript;
        sourceManifest = entry;
      };
      meta = {
        sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
        description = "Apple-distributed fonts from ${entry.name}";
        homepage = "https://developer.apple.com/fonts/";
        license = lib.licenses.unfree;
        platforms = lib.platforms.unix;
      };
    };
  packages = lib.listToAttrs (
    map (entry: {
      inherit (entry) name;
      value = mkFont entry (fetchurl {
        inherit (entry) url hash;
        name = "${entry.name}-${entry.version}.${entry.kind}";
        # Source archives carry the same redistribution restrictions.
        meta.license = lib.licenses.unfree;
        preferLocalBuild = true;
        derivationArgs.allowSubstitutes = false;
      });
    }) manifest.sources
  );
  assets = lib.filterAttrs (name: _: lib.hasPrefix "apple-asset-" name) packages;
  developerSources = lib.filterAttrs (name: _: !lib.hasPrefix "apple-asset-" name) packages;
  fromSource =
    { manifestFile }:
    let
      entry = builtins.fromJSON (builtins.readFile manifestFile);
    in
    mkFont entry (fetchurl {
      inherit (entry) url hash;
      name = "${entry.name}-${entry.version}.${entry.kind}";
      meta.license = lib.licenses.unfree;
      preferLocalBuild = true;
      derivationArgs.allowSubstitutes = false;
    });
  fromArchive =
    {
      manifestFile,
      src ? null,
    }:
    let
      entry = builtins.fromJSON (builtins.readFile manifestFile);
      archive =
        if src != null then
          src
        else
          requireFile {
            name = entry.archiveName;
            inherit (entry) hash;
            message = ''
              Supply the recorded font archive ${entry.archiveName} from your Mac:
                nix-store --add-fixed sha256 ${entry.archiveName}
              See apple-fonts/README.md for the export command and limitations.
            '';
          };
    in
    mkFont entry archive;
in
buildEnv {
  pname = "apple-fonts";
  inherit (manifest) version;
  # Keep every tracked Apple developer distribution in the consolidated output.
  paths = lib.attrValues assets ++ lib.attrValues developerSources;
  ignoreCollisions = false;
  checkCollisionContents = true;
  derivationArgs = {
    strictDeps = true;
    preferLocalBuild = true;
    allowSubstitutes = false;
  };
  passthru = {
    inherit
      assets
      fromArchive
      fromSource
      updateScript
      ;
    catalogManifest = manifest;
  };
  meta = {
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    description = "Selected macOS Font8 catalog assets and Apple developer fonts with pinned sources";
    homepage = "https://support.apple.com/en-ie/122869";
    license = lib.licenses.unfree;
    platforms = lib.platforms.unix;
  };
}
