{
  callPackage,
  fetchFromGitHub,
  lib,
  stdenv,
  spotxArgs ? [
    "--hide"
    "--noninteractive"
    "--nocolor"
  ],
}:

let
  source = import ./source.nix;
  spotxSource = fetchFromGitHub source.spotx;
  supportedSpotxArgs = [
    "--devmode"
    "--hide"
    "--lyricsbg"
    "--nocolor"
    "--noexp"
    "--noninteractive"
    "--oldui"
    "--premium"
  ];
  unsupportedSpotxArgs = lib.subtractLists supportedSpotxArgs spotxArgs;
  adapterArgs = { inherit source spotxArgs spotxSource; };
in
assert lib.assertMsg (unsupportedSpotxArgs == [ ]) ''
  spotify-spotx only accepts non-interactive, build-safe SpotX arguments.
  Unsupported arguments: ${lib.concatStringsSep ", " unsupportedSpotxArgs}
'';
if stdenv.hostPlatform.isDarwin then
  callPackage ./darwin.nix adapterArgs
else if stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isx86_64 then
  callPackage ./linux.nix adapterArgs
else
  throw "spotify-spotx does not support ${stdenv.hostPlatform.system}"
