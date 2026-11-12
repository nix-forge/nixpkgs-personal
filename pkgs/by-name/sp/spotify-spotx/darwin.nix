{
  callPackage,
  replaceVars,
  bash,
  coreutils,
  darwin,
  fetchurl,
  file,
  findutils,
  gnugrep,
  gnused,
  gnutar,
  lib,
  perl,
  rcodesign,
  source,
  spotxArgs,
  spotxSource,
  stdenvNoCC,
  python3,
  unzip,
  util-linux,
  writeText,
  zip,
}:

let
  spotifySource = fetchurl { inherit (source.spotify) url hash; };
  entitlements = writeText "spotify-spotx-entitlements.plist" (
    builtins.readFile ./entitlements.plist
  );
in
stdenvNoCC.mkDerivation {
  pname = "spotify-spotx";
  inherit (source) version;

  dontUnpack = true;
  dontFixup = true;
  strictDeps = true;

  # spicetify-nix appends its resource changes to postInstall. The explicit
  # final phase therefore signs the complete SpotX and Spicetify bundle.
  phases = [
    "installPhase"
    "signSpotifyBundlePhase"
    "installCheckPhase"
  ];

  nativeBuildInputs = [
    bash
    coreutils
    darwin.DarwinTools
    darwin.system_cmds
    (lib.getBin file)
    findutils
    gnugrep
    gnused
    gnutar
    perl
    rcodesign
    unzip
    util-linux
    zip
  ];

  nativeInstallCheckInputs = [ python3 ];
  postInstallCheck = ''
    python3 ${./scripts/check_app_bundle.py} "$out/Applications/Spotify.app" --expected-version ${lib.escapeShellArg source.version}
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    runHook postInstallCheck
  '';

  installPhase = ''
    source ${
      replaceVars ./scripts/darwin-install-phase.sh {
        inherit spotifySource;
        inherit spotxSource;
        bash = lib.getExe bash;
        sourceVersion = lib.escapeShellArg source.version;
        patchArguments = lib.escapeShellArgs spotxArgs;
      }
    }
  '';

  signSpotifyBundlePhase = ''
    source ${
      replaceVars ./scripts/darwin-sign-bundle.sh {
        rcodesign = lib.getExe rcodesign;
        inherit entitlements;
      }
    }
  '';

  passthru = {
    inherit entitlements spotxArgs spotxSource;
    signingMethod = "rcodesign-recursive-bundle";
    spotxVersion = source.version;
    spotifyVersion = source.version;
    updateScript = [
      (lib.getExe (callPackage ./update.nix { }))
      "--source-directory"
      (builtins.unsafeDiscardStringContext (toString ./.))
    ];
  };

  meta = {
    description = "Music streaming client patched with SpotX-Bash and signed as a complete macOS bundle";
    homepage = "https://github.com/SpotX-Official/SpotX-Bash";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  }
  // lib.optionalAttrs (
    stdenvNoCC.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
  ) { mainDarwinApp = "Spotify.app"; };
}
