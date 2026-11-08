{
  codex,
  callPackage,
  fetchFromGitHub,
  fetchurl,
  lib,
  lld,
  llvmPackages,
  stdenv,
}:
let
  source = import ./source.nix;
  system = stdenv.hostPlatform.system;
  # Keep metadata readable on unsupported hosts for package discovery.
  runtime = source.v8.sources.${system} or source.v8.sources.x86_64-linux;
in
(codex.override {
  librusty_v8 = fetchurl (runtime.archive // { name = "librusty_v8-${source.v8.version}"; });
  librusty_v8_src_binding = fetchurl (
    runtime.binding // { name = "src_binding-${source.v8.version}"; }
  );
}).overrideAttrs
  (old: {
    # Release outputs are stripped; retain configured compiler parallelism.
    # Release outputs are stripped; avoid generating discarded line tables.
    # Linux LLD also avoids GNU ld's large final-link working set.
    nativeBuildInputs =
      (old.nativeBuildInputs or [ ]) ++ lib.optionals stdenv.hostPlatform.isLinux [ lld ];
    env =
      (old.env or { })
      // lib.optionalAttrs stdenv.hostPlatform.isLinux {
        CARGO_PROFILE_RELEASE_DEBUG = "false";
        NIX_CFLAGS_LINK = lib.concatStringsSep " " (
          lib.filter (flag: flag != "") [
            ((old.env or { }).NIX_CFLAGS_LINK or "")
            "-B${llvmPackages.bintools}/bin -fuse-ld=lld"
          ]
        );
      };
    inherit (source) version cargoHash;
    buildCommit = source.rev;
    src = fetchFromGitHub {
      owner = "openai";
      repo = "codex";
      inherit (source) rev hash;
    };
    passthru = old.passthru // {
      updateScript = [
        (lib.getExe (callPackage ./update.nix { }))
        "--source-directory"
        (builtins.unsafeDiscardStringContext (toString ./.))
      ];
    };
    meta = old.meta // {
      maintainers = [ ];
      platforms = builtins.attrNames source.v8.sources;
      sourceProvenance = with lib.sourceTypes; [
        fromSource
        binaryNativeCode
      ];
    };
  })
