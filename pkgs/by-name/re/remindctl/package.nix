{
  callPackage,
  replaceVars,
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

let
  pname = "remindctl";
  source = import ./source.nix;
  # The binary-only release archive omits its MIT notice. Keep the matching
  # release's notice pinned; a changed notice requires review during updates.
  licenseSource = fetchurl {
    url = "https://raw.githubusercontent.com/openclaw/remindctl/v${source.version}/LICENSE";
    hash = "sha256-FCk1VreZQHRRI9AWDHHSftDp/puKhICT8+149IU8qv4=";
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  inherit pname;
  inherit (source) version;

  src = fetchurl source.src;
  agentSkillSource = fetchurl source.skill;

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  strictDeps = true;

  dontConfigure = true;
  dontBuild = true;
  # Both upstream Mach-O slices are signed. Preserve the release executable
  # instead of stripping it and changing the identity used for Reminders access.
  dontFixup = true;

  installPhase = ''
    source ${
      replaceVars ./scripts/install-phase.sh {
        inherit pname;
        inherit licenseSource;
      }
    }
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        inherit licenseSource;
        inherit pname;
        inherit (finalAttrs) version;
      }
    }
  '';

  passthru = {
    agentSkill = "${finalAttrs.finalPackage}/share/agent-skills/apple-reminders";
    updateScript = [
      (lib.getExe (callPackage ./update.nix { }))
      "--source-directory"
      (builtins.unsafeDiscardStringContext (toString ./.))
    ];
  };

  meta = {
    description = "Fast command-line access to Apple Reminders";
    homepage = "https://remindctl.sh";
    downloadPage = "https://github.com/openclaw/remindctl/releases";
    license = lib.licenses.mit;
    mainProgram = "remindctl";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
