{
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

assert lib.assertMsg (lib.versionAtLeast source.version spotify.version) ''
  Spotify ${spotify.version} is newer than SpotX-Bash's supported version ${source.version}.
  Update spotify-spotx before updating Spotify.
'';
spotify.overrideAttrs (old: {
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
    fakeBin="$TMPDIR/spotx-fake-bin"
    install -d "$fakeBin"
    printf '%s\n' '#!/bin/sh' 'exit 1' > "$fakeBin/curl"
    chmod +x "$fakeBin/curl"

    export HOME="$TMPDIR/spotx-home"
    export PATH="$fakeBin:$PATH"
    export SPOTX_BUILD_MODE=true
    mkdir -p "$HOME"

    ${lib.getExe bash} ${spotxSource}/spotx.sh \
      -P "$out/share/spotify" \
      ${lib.escapeShellArgs spotxArgs}

    unzip -p "$out/share/spotify/Apps/xpui.spa" > "$TMPDIR/spotx-xpui-content"
    grep -Fq '//# SpotX was here' "$TMPDIR/spotx-xpui-content"
    rm -f "$out/share/spotify/spotify.bak"
    rm -f "$out/share/spotify/Apps/xpui.bak"
  '';

  passthru = (old.passthru or { }) // {
    inherit spotxArgs spotxSource;
    spotxVersion = source.version;
    spotifyVersion = spotify.version;
    unpatchedSpotify = spotify;
    updateScript = [ ./update.py ];
  };

  meta = (old.meta or { }) // {
    description = "Spotify for Linux patched with SpotX-Bash";
    homepage = "https://github.com/SpotX-Official/SpotX-Bash";
    platforms = [ "x86_64-linux" ];
  };
})
