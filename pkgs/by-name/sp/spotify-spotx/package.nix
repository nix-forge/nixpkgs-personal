{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  bash,
  coreutils,
  file,
  findutils,
  gnugrep,
  gnused,
  gnutar,
  perl,
  util-linux,
  unzip,
  writeText,
  zip,
  darwin,
}:

let
  pname = "spotify-spotx";
  source = import ./source.nix;

  spotxSrc = fetchFromGitHub source.spotx;
  spotifySrc = fetchurl { inherit (source.spotify) url hash; };
  entitlements = writeText "spotify-spotx-entitlements.plist" (
    builtins.readFile ./entitlements.plist
  );
in
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;

  dontUnpack = true;
  dontFixup = true;
  strictDeps = true;

  # Spicetify derives its final package with `spotify.overrideAttrs`, appending
  # its resource changes to this package's post-install work. Keep signing in
  # an explicit final phase so it covers the completed app bundle rather than
  # only the pre-Spicetify executable files. This remains a normal sandboxed
  # Nix build; darwin.sigtool provides the sandbox-compatible Mach-O signer.
  phases = [
    "installPhase"
    "signSpotifyBundlePhase"
  ];

  nativeBuildInputs = [
    bash
    coreutils
    file
    findutils
    gnugrep
    gnused
    gnutar
    perl
    util-linux
    unzip
    zip
    darwin.cctools
    darwin.DarwinTools
    darwin.sigtool
    darwin.system_cmds
  ];

  installPhase = ''
    runHook preInstall

    install -d "$out/Applications/Spotify.app"
    tar -xpf ${spotifySrc} -C "$out/Applications/Spotify.app"
    chmod -R u+rwX "$out/Applications/Spotify.app"

    fakeBin="$TMPDIR/fake-bin"
    install -d "$fakeBin"
    printf '%s\n' '#!/bin/sh' 'exit 1' > "$fakeBin/curl"
    chmod +x "$fakeBin/curl"
    cat > "$fakeBin/xattr" <<'EOF'
    #!/bin/sh
    if [ "$#" -eq 2 ] && [ "$1" = "-cr" ]; then
      exit 0
    fi
    printf 'unsupported xattr invocation: %s\n' "$*" >&2
    exit 1
    EOF
    chmod +x "$fakeBin/xattr"

    export HOME="$TMPDIR/home"
    install -d "$HOME"
    export PATH="$fakeBin:$PATH:/usr/bin:/bin:/usr/sbin:/sbin"

    spotxScript="$TMPDIR/spotx.sh"
    sed 's|/usr/bin/xattr|xattr|g' ${spotxSrc}/spotx.sh > "$spotxScript"

    bash "$spotxScript" \
      --force \
      --blockupdates \
      --premium \
      --noexp \
      --skipcodesign \
      -P "$out/Applications"

    rm -f "$out/Applications/Spotify.app/Contents/MacOS/Spotify.bak"
    rm -f "$out/Applications/Spotify.app/Contents/Resources/Apps/xpui.bak"

    runHook postInstall
    runHook postInstallCheck
  '';

  signSpotifyBundlePhase = ''
    runHook preSignSpotifyBundle

    export CODESIGN_ALLOCATE="${darwin.cctools}/bin/codesign_allocate"
    while IFS= read -r executable; do
      if file "$executable" | grep -q 'Mach-O'; then
        codesign --force --entitlements ${entitlements} --sign - "$executable"
      fi
    done < <(find "$out/Applications/Spotify.app" -type f -perm -0100)

    runHook postSignSpotifyBundle
  '';

  passthru = {
    inherit entitlements;
    updateScript = [ ./update.py ];
  };

  meta = {
    description = "Spotify for macOS patched with SpotX and ready for Spicetify post-install theming";
    homepage = "https://github.com/SpotX-Official/SpotX-Bash";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
