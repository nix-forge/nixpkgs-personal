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
  # Independently reviewed outputs that contain upstream-built code or assets.
  # Keep this list aligned with docs/source-provenance-review.md when adding a
  # public package or changing its build process.
  nonSourceNames = [
    "anthropic-skills"
    "apple-color-emoji"
    "apple-fonts"
    "aurral"
    "bitwarden-desktop"
    "cadcraft"
    "chatgpt-latest"
    "claude-desktop"
    "codex-latest"
    "craft-fonts"
    "craft-launcher"
    "deckcraft"
    "designcraft"
    "effectcraft"
    "emojione-legacy"
    "figcraft"
    "filmcraft"
    "firefox-emoji"
    "google-fonts-design"
    "gridcraft"
    "jellyfin-plugin-moonbase"
    "libreoffice"
    "lightcraft"
    "linearmouse"
    "microsoft-teams"
    "moonfin"
    "mplus-outline-fonts-compatible"
    "pdfcraft"
    "photocraft"
    "psscriptanalyzer"
    "rea"
    "remindctl"
    "scrypted-plugin-homekit"
    "soundcraft"
    "spotify-spotx"
    "steam"
    "stirling-pdf-v3"
    "ttf-ms-win11-auto"
    "twemoji-color-font-optional"
    "vectorcraft"
    "wardrowbe-frontend"
    "wootility"
    "wordcraft"
  ];
  provenanceAudit = lib.mapAttrs (
    name: package:
    let
      hasNonSource = lib.any (source: !(source.isSource or false)) (package.meta.sourceProvenance or [ ]);
    in
    assert lib.assertMsg (
      hasNonSource == builtins.elem name nonSourceNames
    ) "${name}: source provenance differs from the reviewed package inventory";
    hasNonSource
  ) supported;
  # Reviewed upstream licenses, independent of the values in package.meta.
  unfreeNames = [
    "apple-color-emoji"
    "apple-fonts"
    "chatgpt-latest"
    "claude-desktop"
    "microsoft-teams"
    "mutant-standard-emoji"
    "spotify-spotx"
    "steam"
    "stirling-pdf-engine"
    "stirling-pdf-v3"
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
          rea = false;
          stirling-pdf-v3 = false;
        }
        # The Arlo build toolchain pulls cargo-bootstrap, which has independent
        # non-source provenance. The inventory above checks Arlo's own output.
        // lib.optionalAttrs (system == "x86_64-linux") { scrypted-plugin-homekit = false; }
        // lib.optionalAttrs base.stdenv.hostPlatform.isDarwin {
          bitwarden-desktop = false;
          libreoffice = false;
          linearmouse = false;
          remindctl = false;
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
    openaiFullDenied = !(succeeds (packages.openai-skills.override { includeRestricted = true; }));
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
  !succeeds selected.apple-fonts && !succeeds selectedOverlay.apple-fonts
) "A selective predicate must still reject unrelated unfree packages";
builtins.deepSeq provenanceAudit (
  builtins.deepSeq defaultPolicy (
    builtins.deepSeq allowed (
      builtins.deepSeq sourcePolicy {
        inherit
          provenanceAudit
          defaultPolicy
          allowed
          sourcePolicy
          variants
          ;
      }
    )
  )
)
