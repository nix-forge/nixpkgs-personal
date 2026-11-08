{
  callPackage,
  replaceVars,
  alsa-lib,
  fetchFromGitHub,
  ffmpeg,
  flutter347,
  lib,
  libarchive,
  libass,
  libsecret,
  copyDesktopItems,
  desktop-file-utils,
  makeDesktopItem,
  meta,
  mpv-unwrapped,
  patchelf,
  python3,
  sqlite,
  webkitgtk_4_1,
}:
let
  source = import ./source.nix;
in
flutter347.buildFlutterApplication {
  pname = "moonfin";
  inherit (source) version;
  inherit meta;
  src = fetchFromGitHub {
    owner = "Moonfin-Client";
    repo = "Moonfin-Core";
    rev = source.sourceRev;
    hash = source.sourceHash;
  };
  pubspecLock = lib.importJSON ./pubspec.lock.json;
  gitHashes = lib.importJSON ./git-hashes.json;
  strictDeps = true;
  nativeBuildInputs = [
    copyDesktopItems
    desktop-file-utils
    patchelf
  ];
  buildInputs = [
    alsa-lib
    ffmpeg
    libarchive
    libass
    libsecret
    mpv-unwrapped
    sqlite
    webkitgtk_4_1
  ];
  desktopItems = [
    (makeDesktopItem {
      name = "org.moonfin.linux";
      desktopName = "Moonfin";
      genericName = "Media player";
      comment = meta.description;
      terminal = false;
      exec = "moonfin";
      tryExec = "moonfin";
      icon = "org.moonfin.linux";
      categories = [
        "AudioVideo"
        "Player"
      ];
    })
  ];
  postInstall = builtins.readFile ./scripts/linux-post-install.sh;
  postFixup = ''
    source ${
      replaceVars ./scripts/linux-post-fixup.sh {
        mediaLibraryPath = lib.makeLibraryPath [
          mpv-unwrapped
          sqlite
        ];
      }
    }
  '';
  postInstallCheck = ''
    ${lib.getExe python3} ${./scripts/check_desktop_entry.py} "$out" "org.moonfin.linux.desktop" "moonfin"
  '';
  doInstallCheck = true;
  passthru.updateScript = [
    (lib.getExe (callPackage ./update.nix { }))
    "--source-directory"
    (builtins.unsafeDiscardStringContext (toString ./.))
  ];
  installCheckPhase = builtins.readFile ./scripts/linux-install-check-phase.sh;
}
