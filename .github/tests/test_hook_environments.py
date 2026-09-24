"""Keep local and sandbox hook sets aligned after upstream extraction."""

import json
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class HookEnvironmentTests(unittest.TestCase):
    def test_host_hooks_remain_enabled_without_entering_the_sandbox(self):
        expression = r"""
                    let
                        root = ROOT;
                        dev = builtins.getFlake (root + "/flake/dev");
                        lib = dev.inputs.nixpkgs.lib;
                        inspect = system:
                            let
                                pkgs = dev.inputs.nixpkgs.legacyPackages.${system};
                                module = import (root + "/flake/dev/git-hooks.nix") {
                                    inherit lib;
                                    inputs = {
                                        self.outPath = root;
                                        git-hooks-nix.flakeModule = {};
                                        git-hooks-nix.lib.${system}.run = settings: settings;
                                    };
                                };
                                result = module.perSystem {
                                    inherit pkgs system;
                                    config.treefmt.build.wrapper = pkgs.hello;
                                };
                                enabled = hooks: lib.mapAttrs (_: hook: hook.entry or "builtin")
                                    (lib.filterAttrs (_: hook: hook.enable or false) hooks);
                            in {
                                local = enabled result.pre-commit.settings.hooks;
                                sandbox = enabled result.checks.pre-commit.hooks;
                            };
                    in {
                        linux = inspect "x86_64-linux";
                        darwin = inspect "aarch64-darwin";
                    }
        """.replace("ROOT", json.dumps(str(ROOT)))
        result = json.loads(
            subprocess.check_output(
                ["nix", "eval", "--impure", "--json", "--expr", expression], text=True
            )
        )
        darwin = result["darwin"]
        self.assertEqual(darwin["local"], darwin["sandbox"])
        self.assertEqual(result["linux"]["local"], result["linux"]["sandbox"])
        for system in result.values():
            self.assertTrue(system["sandbox"])
            for name, command in system["sandbox"].items():
                self.assertEqual(command, system["local"][name])
            self.assertIn("treefmt", system["sandbox"])


if __name__ == "__main__":
    unittest.main()
