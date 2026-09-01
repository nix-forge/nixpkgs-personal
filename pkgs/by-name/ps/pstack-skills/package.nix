{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  findutils,
  gnused,
}:

let
  pname = "pstack-skills";
  source = import ./source.nix;
in
stdenvNoCC.mkDerivation (_finalAttrs: {
  inherit pname;
  inherit (source) version;

  src = fetchFromGitHub source.src;
  nativeBuildInputs = [
    findutils
    gnused
  ];
  strictDeps = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    skill_root="$out/share/agent-skills"
    mkdir -p "$skill_root"
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
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    installed_skill_count="$(find "$out/share/agent-skills" -mindepth 1 -maxdepth 1 -type d | wc -l)"
    test "$installed_skill_count" -gt 0
    test "$installed_skill_count" -eq "$(find "$out/share/agent-skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | wc -l)"
    while IFS= read -r skill_file; do
      grep -q '^---$' "$skill_file"
      grep -Eq '^name: pstack-[a-z0-9-]+$' "$skill_file"
    done < <(find "$out/share/agent-skills" -mindepth 2 -maxdepth 2 -name SKILL.md -type f | sort)

    runHook postInstallCheck
  '';

  passthru.updateScript = [ ./update.py ];

  meta = {
    description = "pstack Agent Skills catalog";
    homepage = "https://github.com/cursor/plugins/tree/main/pstack";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
})
