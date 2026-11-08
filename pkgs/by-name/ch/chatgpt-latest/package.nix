{
  chatgpt,
  codex,
  callPackage,
  lib,
  stdenv,
  writers,
}:
# Keep upstream's packaging and backend injection; update only its release map.
(chatgpt.override { inherit codex; }).overrideAttrs (
  old:
  {
    # The signed Darwin application must not pass through generic mutation hooks.
    dontFixup = stdenv.hostPlatform.isDarwin || (old.dontFixup or false);
    passthru = old.passthru // {
      sources = import ./source.nix;
      updateScript = [
        (lib.getExe (callPackage ./update.nix { }))
        "--source-directory"
        (builtins.unsafeDiscardStringContext (toString ./.))
      ];
    };
    meta =
      old.meta
      // {
        maintainers = [ ];
      }
      // lib.optionalAttrs (
        stdenv.hostPlatform.isDarwin && lib.versionAtLeast (lib.versions.majorMinor lib.version) "26.11"
      ) { mainDarwinApp = "ChatGPT.app"; };
  }
  // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
    # Executing the signed GUI bundle during install checks makes macOS protect
    # it before Nix finalizes the output. Verify its actual version without launch.
    versionCheckProgram = writers.writePython3 "chatgpt-bundle-version" { } ./bundle_version.py;
    versionCheckProgramArg = "${placeholder "out"}/Applications/ChatGPT.app/Contents/Info.plist";
  }
)
