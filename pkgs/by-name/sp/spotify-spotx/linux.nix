{
  callPackage,
  replaceVars,
  bash,
  desktop-file-utils,
  python3,
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

assert lib.assertMsg (lib.versionAtLeast source.version spotify.version) ''
  Spotify ${spotify.version} is newer than SpotX-Bash's supported version ${source.version}.
  Update spotify-spotx before updating Spotify.
'';
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

  nativeInstallCheckInputs = (old.nativeInstallCheckInputs or [ ]) ++ [
    desktop-file-utils
    python3
  ];
  doInstallCheck = true;
  postInstallCheck = (old.postInstallCheck or "") + ''
    desktop-file-validate "$out/share/applications/spotify.desktop"
    python3 ${./scripts/check_desktop_entry.py} "$out" "spotify.desktop" "spotify"
  '';

  meta = (old.meta or { }) // {
    maintainers = [ ];
    description = "Music streaming client patched with SpotX-Bash";
    homepage = "https://github.com/SpotX-Official/SpotX-Bash";
    platforms = [ "x86_64-linux" ];
  };
})
