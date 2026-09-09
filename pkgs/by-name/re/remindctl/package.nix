{
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
    runHook preInstall

    install -Dm755 remindctl "$out/bin/${pname}"
    install -Dm644 ${licenseSource} "$out/share/doc/${pname}/LICENSE"
    install -Dm644 "$agentSkillSource" "$out/share/agent-skills/apple-reminders/SKILL.md"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    cmp ${licenseSource} "$out/share/doc/${pname}/LICENSE"

    test "$("$out/bin/${pname}" --version)" = "${finalAttrs.version}"
    grep -q '^name: apple-reminders$' "$out/share/agent-skills/apple-reminders/SKILL.md"

    runHook postInstallCheck
  '';

  passthru = {
    agentSkill = "${finalAttrs.finalPackage}/share/agent-skills/apple-reminders";
    updateScript = [
      "python3"
      "pkgs/by-name/re/remindctl/update.py"
    ];
  };

  meta = {
    description = "Fast command-line access to Apple Reminders";
    homepage = "https://remindctl.sh";
    downloadPage = "https://github.com/openclaw/remindctl/releases";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
