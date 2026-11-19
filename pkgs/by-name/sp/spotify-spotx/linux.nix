{
  callPackage,
  replaceVars,
  bash,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  lib,
  perl,
  source,
  spotify,
  spotxArgs,
  spotxSource,
  unzip,
  util-linux,
  zip,
}:

if !(lib.versionAtLeast source.version spotify.version) then
  throw ''
    Spotify ${spotify.version} is newer than SpotX-Bash's supported version ${source.version}.
    Update spotify-spotx before updating Spotify.
  ''
else
  spotify.overrideAttrs (old: {
    strictDeps = true;
    pname = "spotify-spotx";

    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
      bash
      coreutils
      findutils
      gnugrep
      gnused
      perl
      unzip
      util-linux
      zip
    ];

    # SpotX patches stock Spotify first. spicetify-nix then appends its own
    # postInstall hook, so themes and extensions always see the SpotX result.
    postInstall = (old.postInstall or "") + ''
      source ${
        replaceVars ./scripts/linux-post-install.sh {
          bash = lib.getExe bash;
          inherit spotxSource;
          patchArguments = lib.escapeShellArgs spotxArgs;
        }
      }
    '';

    passthru = (old.passthru or { }) // {
      inherit spotxArgs spotxSource;
      spotxVersion = source.version;
      spotifyVersion = spotify.version;
      unpatchedSpotify = spotify;
      updateScript = [
        (lib.getExe (callPackage ./update.nix { }))
        "--source-directory"
        (builtins.unsafeDiscardStringContext (toString ./.))
      ];
    };

    meta = (old.meta or { }) // {
      maintainers = [ ];
      description = "Music streaming client patched with SpotX-Bash";
      homepage = "https://github.com/SpotX-Official/SpotX-Bash";
      platforms = [ "x86_64-linux" ];
    };
  })
