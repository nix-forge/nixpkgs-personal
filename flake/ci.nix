{ self, ... }:
let
  manualChecks = builtins.mapAttrs (
    _: checks: builtins.intersectAttrs { mutant-standard-emoji = null; } checks
  ) self.checks;
in
{
  flake = {
    # Portable tooling is enforced once by the required Linux lint job. Native
    # Swift tooling stays in its required macOS jobs and local Git hooks.
    lintChecks = builtins.mapAttrs (_: checks: { inherit (checks) pre-commit treefmt; }) self.checks;
    # Mutant Standard Emoji takes 54+ minutes to compile on a hosted runner and
    # produces the same platform-independent font on every system. Keep its
    # exhaustive 7,829-glyph validation available through the manual CI audit.
    inherit manualChecks;
    ciChecks = builtins.mapAttrs (
      system: checks:
      removeAttrs checks (
        builtins.attrNames self.lintChecks.${system} ++ builtins.attrNames manualChecks.${system}
      )
    ) self.checks;
  };
}
