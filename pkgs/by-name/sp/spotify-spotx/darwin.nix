{
  bash,
  coreutils,
  darwin,
  fetchurl,
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
  ];

  nativeBuildInputs = [
    bash
    coreutils
    darwin.DarwinTools
    darwin.system_cmds
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

  installPhase = ''
    runHook preInstall

    app="$out/Applications/Spotify.app"
    install -d "$app"
    tar -xpf ${spotifySource} -C "$app"
    chmod -R u+rwX "$app"

    # Keep the upstream patcher offline and replace its one absolute host-tool
    # call. Any unexpected curl use fails even if a builder permits networking.
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

    export HOME="$TMPDIR/spotx-home"
    export PATH="$fakeBin:$PATH"
    export SPOTX_BUILD_MODE=true
    install -d "$HOME"

    spotxScript="$TMPDIR/spotx.sh"
    sed 's|/usr/bin/xattr|xattr|g' ${spotxSource}/spotx.sh > "$spotxScript"

    ${lib.getExe bash} "$spotxScript" \
      -F ${lib.escapeShellArg source.version} \
      -P "$out/Applications" \
      --blockupdates \
      --skipcodesign \
      ${lib.escapeShellArgs spotxArgs}

    unzip -p "$app/Contents/Resources/Apps/xpui.spa" > "$TMPDIR/spotx-xpui-content"
    grep -Fq '//# SpotX was here' "$TMPDIR/spotx-xpui-content"
    rm -f "$app/Contents/MacOS/Spotify.bak"
    rm -f "$app/Contents/Resources/Apps/xpui.bak"

    runHook postInstall
    runHook postInstallCheck
  '';

  signSpotifyBundlePhase = ''
    runHook preSignSpotifyBundle

    app="$out/Applications/Spotify.app"
    ${lib.getExe rcodesign} sign \
      --code-signature-flags runtime \
      --entitlements-xml-file ${entitlements} \
      "$app"
    test -s "$app/Contents/_CodeSignature/CodeResources"

    runHook postSignSpotifyBundle
  '';

  passthru = {
    inherit entitlements spotxArgs spotxSource;
    signingMethod = "rcodesign-recursive-bundle";
    spotxVersion = source.version;
    spotifyVersion = source.version;
    updateScript = [ ./update.py ];
  };

  meta = {
    description = "Spotify for macOS patched with SpotX-Bash and signed as a complete app bundle";
    homepage = "https://github.com/SpotX-Official/SpotX-Bash";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
