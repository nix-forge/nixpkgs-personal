# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall

skill_root="$out/share/agent-skills"
mkdir -p "$skill_root"
install -Dm644 "$src/pstack/LICENSE" "$out/share/doc/@pname@/LICENSE"
for source_skill in "$src"/pstack/skills/*; do
  test -f "$source_skill/SKILL.md" || continue
  skill_name="$(basename "$source_skill")"
  target_name="pstack-$skill_name"
  target_skill="$TMPDIR/$target_name"
  cp -R --no-preserve=ownership "$source_skill" "$target_skill"
  chmod -R u+w "$target_skill"
  sed -i "0,/^name: .*$/s//name: $target_name/" "$target_skill/SKILL.md"
  cp -R --no-preserve=ownership "$target_skill" "$skill_root/$target_name"
done

runHook postInstall
