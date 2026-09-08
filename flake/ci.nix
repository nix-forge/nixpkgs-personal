{ self, ... }: {
  flake = {
    # Portable tooling is enforced once by the required Linux lint job. Native
    # Swift tooling stays in its required macOS jobs and local Git hooks.
    lintChecks = builtins.mapAttrs (_: checks: { inherit (checks) pre-commit treefmt; }) self.checks;
    ciChecks = builtins.mapAttrs (
      system: checks: removeAttrs checks (builtins.attrNames self.lintChecks.${system})
    ) self.checks;
  };
}
