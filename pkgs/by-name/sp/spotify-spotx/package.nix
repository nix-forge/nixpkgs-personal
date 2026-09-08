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
# Select the build recipe here; each adapter declares its supported architectures
# in meta.platforms. Keep metadata readable on unsupported hosts for discovery.
if stdenv.hostPlatform.isDarwin then
  callPackage ./darwin.nix adapterArgs
else
  callPackage ./linux.nix adapterArgs
