{
  callPackage,
  replaceVars,
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  python3,
  writeText,
  includeRestricted ? false,
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
    source ${
      replaceVars ./scripts/install-phase.sh {
        catalog_py = "${./catalog.py}";
        catalog_json = "${./catalog.json}";
        inherit selection;
        readme = "${./README.md}";
        inherit pname;
      }
    }
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    source ${
      replaceVars ./scripts/install-check-phase.sh {
        catalog_py = "${./catalog.py}";
        catalog_json = "${./catalog.json}";
        inherit selection;
      }
    }
  '';
  passthru = {
    inherit availableSkills freeSkills;
    restrictedSkills = lib.subtractLists freeSkills availableSkills;
    updateScript = [
      (lib.getExe (callPackage ./update.nix { }))
      "--source-directory"
      (builtins.unsafeDiscardStringContext (toString ./.))
    ];
  };
  meta = {
    description = "Selected agent skills from OpenAI with reviewed component licensing";
    homepage = "https://github.com/openai/skills";
    license = map (name: lib.licenses.${name}) licenseNames;
    sourceProvenance = [
      lib.sourceTypes.fromSource
    ]
    ++ lib.optional hasFonts lib.sourceTypes.binaryBytecode;
    platforms = lib.platforms.all;
  };
}
