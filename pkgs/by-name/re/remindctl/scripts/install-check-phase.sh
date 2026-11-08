# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstallCheck

cmp @licenseSource@ "$out/share/doc/@pname@/LICENSE"

test "$("$out/bin/@pname@" --version)" = "@version@"
grep -q '^name: apple-reminders$' "$out/share/agent-skills/apple-reminders/SKILL.md"

runHook postInstallCheck
