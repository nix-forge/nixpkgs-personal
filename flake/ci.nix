{ self, ... }:
let
  manualChecks = builtins.mapAttrs (
    _: checks: builtins.intersectAttrs { mutant-standard-emoji = null; } checks
  ) self.checks;
  localOnlyChecks = builtins.mapAttrs (
    _: checks: builtins.intersectAttrs { apple-color-emoji = null; } checks
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
    # Apple Color Emoji processing is intentionally excluded from hosted CI by
    # repository policy until the third-party artwork permissions are resolved.
    # The full check remains available to local, authorized builders.
    inherit localOnlyChecks;
    ciChecks = builtins.mapAttrs (
      system: checks:
      removeAttrs checks (
        builtins.attrNames self.lintChecks.${system}
        ++ builtins.attrNames manualChecks.${system}
        ++ builtins.attrNames localOnlyChecks.${system}
      )
    ) self.checks;
  };
}
