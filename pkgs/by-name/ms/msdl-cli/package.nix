{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
let
  source = import ./source.nix;
in
buildGoModule {
  pname = "msdl-cli";
  inherit (source) version vendorHash;

  src = fetchFromGitHub {
    owner = "starkSV";
    repo = "windows-iso-downloader";
    inherit (source) rev hash;
  };

  sourceRoot = "source/cli";

  subPackages = [ "." ];
  postInstall = builtins.readFile ./scripts/post-install.sh;

  meta = {
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    description = "CLI for obtaining Microsoft Windows ISO download links";
    homepage = "https://github.com/starkSV/windows-iso-downloader";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "msdl";
  };
}
