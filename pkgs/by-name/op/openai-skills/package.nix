{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  python3,
  writeText,
  includeRestricted ? true,
  selectedSkills ? null,
}:
let
  pname = "openai-skills";
  source = import ./source.nix;
  inventory = builtins.fromJSON (builtins.readFile ./catalog.json);
  availableSkills = builtins.attrNames inventory.skills;
  freeSkills = builtins.filter (
    name: !(builtins.elem "unfree" inventory.skills.${name}.licenses)
  ) availableSkills;
  names =
    if selectedSkills != null then
      selectedSkills
    else if includeRestricted then
      availableSkills
    else
      freeSkills;
  validSelection =
    names != [ ]
    && lib.unique names == names
    && lib.all (name: builtins.hasAttr name inventory.skills) names;
  selection = writeText "${pname}-selection.json" (builtins.toJSON names);
  licenseNames = lib.unique (lib.concatMap (name: inventory.skills.${name}.licenses) names);
  hasFonts = lib.any (name: inventory.skills.${name}.fonts != [ ]) names;
in
assert lib.assertMsg validSelection
  "${pname}: select a nonempty list of unique reviewed skill names";
stdenvNoCC.mkDerivation {
  inherit pname;
  inherit (source) version;
  src = fetchFromGitHub source.src;
  nativeBuildInputs = [ python3 ];
  strictDeps = true;
  dontConfigure = true;
  dontBuild = true;
  # Skill resources are data; generic script fixups would alter upstream files.
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    python3 ${./catalog.py} install "$src" --manifest ${./catalog.json} \
      --selection ${selection} --output "$out"
    install -Dm644 ${./README.md} "$out/share/doc/${pname}/PACKAGING.md"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    python3 ${./catalog.py} verify "$src" --manifest ${./catalog.json} \
      --selection ${selection} --output "$out"
    runHook postInstallCheck
  '';
  passthru = {
    inherit availableSkills freeSkills;
    restrictedSkills = lib.subtractLists freeSkills availableSkills;
    updateScript = [
      "python3"
      "pkgs/by-name/op/openai-skills/update.py"
    ];
  };
  meta = {
    description = "openai Agent Skills with reviewed component selection";
    homepage = "https://github.com/openai/skills";
    license = map (name: lib.licenses.${name}) licenseNames;
    sourceProvenance = [
      lib.sourceTypes.fromSource
    ]
    ++ lib.optional hasFonts lib.sourceTypes.binaryBytecode;
    platforms = lib.platforms.all;
  };
}
