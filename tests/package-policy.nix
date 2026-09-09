# Exercise consumer policy through the public import and overlay interfaces.
{
  nixpkgs,
  system,
  overlay,
}:
let
  base = import nixpkgs {
    inherit system;
    config = {
      allowUnfree = false;
      allowUnfreePredicate = _: false;
      checkMeta = true;
    };
  };
  inherit (base) lib;
  packages = import ../default.nix { pkgs = base; };
  overlaid = base.extend overlay;
  supported = lib.filterAttrs (_: lib.meta.availableOn base.stdenv.hostPlatform) packages;
  # Reviewed upstream licenses, independent of the values in package.meta.
  unfreeNames = [
    "apple-color-emoji"
    "apple-fonts"
    "apple-new-york"
    "apple-sf-arabic"
    "apple-sf-armenian"
    "apple-sf-compact"
    "apple-sf-georgian"
    "apple-sf-hebrew"
    "apple-sf-mono"
    "apple-sf-pro"
    "claude-desktop"
    "microsoft-teams"
    "mutant-standard-emoji"
    "openai-codex-desktop"
    "openai-skills"
    "spotify-spotx"
    "steam"
    "ttf-ms-win11-auto"
    "wootility"
  ];
  succeeds = package: (builtins.tryEval package.drvPath).success;
  defaultPolicy = lib.mapAttrs (
    name: package:
    let
      expected = !(builtins.elem name unfreeNames);
    in
    assert lib.assertMsg (
      succeeds package == expected
    ) "${name}: direct import must honor the reviewed unfree classification";
    assert lib.assertMsg (
      succeeds overlaid.${name} == expected
    ) "${name}: overlay must honor the reviewed unfree classification";
    expected
  ) supported;
  selectedBase = import nixpkgs {
    inherit system;
    config = {
      allowUnfree = false;
      checkMeta = true;
      allowUnfreePredicate =
        package:
        builtins.elem (lib.getName package) [
          "anthropic-skills"
          "openai-skills"
          "ttf-ms-win11-auto"
          "apple-sf-pro"
          "mutant-standard-emoji"
        ];
    };
  };
  selected = import ../default.nix { pkgs = selectedBase; };
  selectedOverlay = selectedBase.extend overlay;
  selectedNames = [
    "anthropic-skills"
    "openai-skills"
    "ttf-ms-win11-auto"
    "apple-sf-pro"
    "mutant-standard-emoji"
  ];
  allowed = map (
    name:
    assert lib.assertMsg (
      succeeds selected.${name} && succeeds selectedOverlay.${name}
    ) "${name}: a package-name predicate must allow the package and its restricted sources";
    name
  ) selectedNames;
  sourceBase = import nixpkgs {
    inherit system;
    config = {
      allowUnfree = true;
      allowNonSource = false;
      checkMeta = true;
    };
  };
  sourcePackages = import ../default.nix { pkgs = sourceBase; };
  sourcePolicy =
    lib.mapAttrs
      (
        name: expected:
        assert lib.assertMsg (
          succeeds sourcePackages.${name} == expected
        ) "${name}: source provenance must enforce allowNonSource independently of licensing";
        expected
      )
      (
        {
          # Free prebuilt fonts still need non-source consent. Text skills do not.
          firefox-emoji = false;
          google-fonts-design = false;
          mplus-outline-fonts-compatible = false;
          twemoji-color-font-optional = false;
          anthropic-skills = false;
          openai-skills = true;
          mattpocock-skills = true;
          pstack-skills = true;
        }
        // lib.optionalAttrs base.stdenv.hostPlatform.isDarwin {
          bitwarden-desktop = false;
          libreoffice = false;
          linearmouse = false;
          remindctl = false;
          t3-code = false;
        }
      );
  variants = {
    anthropicFullDenied =
      !(succeeds (packages.anthropic-skills.override { includeRestricted = true; }));
    anthropicDocumentsAllowed = succeeds (
      selected.anthropic-skills.override {
        selectedSkills = [
          "docx"
          "pdf"
          "pptx"
          "xlsx"
        ];
      }
    );
    openaiFreeAllowed = succeeds (packages.openai-skills.override { includeRestricted = false; });
    openaiFigmaDenied =
      !(succeeds (packages.openai-skills.override { selectedSkills = [ "figma-use" ]; }));
    textOnlyProvenance = succeeds (
      sourcePackages.anthropic-skills.override { selectedSkills = [ "frontend-design" ]; }
    );
    unknownSkillDenied =
      !(succeeds (packages.anthropic-skills.override { selectedSkills = [ "unreviewed" ]; }));
  };
in
assert lib.assertMsg (lib.all (value: value) (
  builtins.attrValues variants
)) "Selected skill variants must preserve license and provenance policy";
assert lib.assertMsg (
  !succeeds selected.apple-sf-mono && !succeeds selectedOverlay.apple-sf-mono
) "A selective predicate must still reject unrelated unfree packages";
builtins.deepSeq defaultPolicy (
  builtins.deepSeq allowed (
    builtins.deepSeq sourcePolicy {
      inherit
        defaultPolicy
        allowed
        sourcePolicy
        variants
        ;
    }
  )
)
