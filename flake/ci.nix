{ self, ... }: {
  flake = {
    lintChecks = builtins.mapAttrs (_: checks: { inherit (checks) pre-commit treefmt; }) self.checks;
    ciChecks = builtins.mapAttrs (
      system: checks: removeAttrs checks (builtins.attrNames self.lintChecks.${system})
    ) self.checks;
  };
}
