{
  lib,
  stdenv,
  callPackage,
  extraPackages ? [ ],
}:

let
  pname = "t3-code";
  source = import ./source.nix;
  meta = {
    description = "Desktop control surface for AI coding agents";
    homepage = "https://t3.codes/";
    downloadPage = "https://github.com/pingdotgg/t3code/releases";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${source.version}";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
    ];
    # The macOS bundle and the Linux build both ship the vendor Electron
    # runtime, so the package needs non-source consent on every platform even
    # though the Linux application code itself is compiled from source.
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
  };
  passthru = {
    inherit (source) appName;
    updateScript = [
      "python3"
      "pkgs/by-name/t3/t3-code/update.py"
    ];
  };
  commonAttrs = {
    inherit pname meta passthru;
    inherit (source) version appName;
  };
in
if stdenv.hostPlatform.isDarwin then
  callPackage ./darwin.nix { inherit commonAttrs source; }
else
  callPackage ./linux.nix { inherit commonAttrs source extraPackages; }
