# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

install -Dm755 remindctl "$out/bin/@pname@"
install -Dm644 @licenseSource@ "$out/share/doc/@pname@/LICENSE"
install -Dm644 "$agentSkillSource" "$out/share/agent-skills/apple-reminders/SKILL.md"

runHook postInstall
