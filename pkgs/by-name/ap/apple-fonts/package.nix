{
  lib,
  stdenvNoCC,
  fetchurl,
  requireFile,
  python3,
  fontconfig,
  _7zz,
  symlinkJoin,
  writeText,
  writeShellApplication,
}:
let
  manifest = builtins.fromJSON (builtins.readFile ./sources.json);
  builder = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./unpack.py
      ./font_support.py
    ];
  };
  updateScript = lib.getExe (writeShellApplication {
    name = "update-apple-fonts";
    runtimeInputs = [
      python3
      fontconfig
      _7zz
    ];
    text = ''
      exec python3 pkgs/by-name/ap/apple-fonts/update.py "$@"
    '';
  });
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
        runHook preInstall
        export XDG_CACHE_HOME="$TMPDIR/font-cache"
        export FONTCONFIG_FILE=${./fonts.conf}
        python3 ${builder}/unpack.py "$src" ${writeText "font-manifest.json" (builtins.toJSON entry)} "$out"
        install -Dm444 ${./README.md} "$out/share/doc/${entry.name}/PACKAGING.md"
        runHook postInstall
      '';
      # Verification in unpack.py checks the manifest, face identities and every
      # copied byte before this derivation succeeds.
      preferLocalBuild = true;
      allowSubstitutes = false;
      passthru = {
        inherit updateScript;
        sourceManifest = entry;
      };
      meta = {
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
  developerFonts = lib.filterAttrs (name: _: !lib.hasPrefix "apple-asset-" name) packages;
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
symlinkJoin {
  pname = "apple-fonts";
  inherit (manifest) version;
  strictDeps = true;
  paths = lib.attrValues assets;
  preferLocalBuild = true;
  allowSubstitutes = false;
  passthru = {
    inherit
      assets
      developerFonts
      fromArchive
      fromSource
      updateScript
      ;
    catalogManifest = manifest;
  };
  meta = {
    description = "Selected macOS Font8 catalog assets with pinned sources";
    homepage = "https://support.apple.com/en-ie/122869";
    license = lib.licenses.unfree;
    platforms = lib.platforms.unix;
  };
}
