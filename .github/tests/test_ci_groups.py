"""Check that lint ownership preserves complete, nonduplicated CI coverage."""

import json
import subprocess
import unittest
from pathlib import Path

MODULE = Path(__file__).resolve().parents[2] / "flake/ci.nix"


class CheckGroupTests(unittest.TestCase):
    def test_groups_follow_check_and_owner_changes(self):
        expression = """
            let
                inspect = native: extraLint:
                    let
                        self = {
                            checks.test-system = {
                                apple-color-emoji = null;
                                mutant-standard-emoji = null;
                                pre-commit = null;
                                treefmt = null;
                            } // native // extraLint;
                            lintChecks = builtins.mapAttrs (_: checks: checks // extraLint)
                                module.flake.lintChecks;
                        };
                        module = import MODULE { inherit self; };
                    in {
                        all = builtins.attrNames self.checks.test-system;
                        lint = builtins.attrNames self.lintChecks.test-system;
                        manual = builtins.attrNames module.flake.manualChecks.test-system;
                        localOnly = builtins.attrNames module.flake.localOnlyChecks.test-system;
                        application = builtins.attrNames module.flake.applicationChecks.test-system;
                        native = builtins.attrNames module.flake.ciChecks.test-system;
                    };
            in {
                before = inspect { first = null; } {};
                added = inspect { first = null; new-check = null; } {};
                removed = inspect { new-check = null; } {};
                application = inspect { designcraft-cli = null; designcraft-gui = null; designcraft-wayland = null; designcraft-licenses = null; designcraft-appstream = null; designcraft-host-tests-artifact = null; effectcraft-host-tests-artifact = null; craft-launcher-host-tests-artifact = null; craft-launcher-quit-state = null; craft-launcher-appimage-runtime = null; figcraft-server = null; artcraft-gui = null; } {};
                newOwner = inspect { first = null; } { new-lint-check = null; };
            }
        """.replace("MODULE", json.dumps(str(MODULE)))
        result = json.loads(
            subprocess.check_output(
                ["nix", "eval", "--impure", "--json", "--expr", expression], text=True
            )
        )
        self.assertEqual(result["before"]["native"], ["first"])
        self.assertEqual(result["before"]["manual"], ["mutant-standard-emoji"])
        self.assertEqual(result["before"]["localOnly"], ["apple-color-emoji"])
        self.assertEqual(result["added"]["native"], ["first", "new-check"])
        self.assertEqual(result["removed"]["native"], ["new-check"])
        self.assertIn("new-lint-check", result["newOwner"]["lint"])
        self.assertNotIn("new-lint-check", result["newOwner"]["native"])
        self.assertEqual(result["application"]["native"], [])
        self.assertEqual(
            result["application"]["application"],
            [
                "artcraft-gui",
                "craft-launcher-appimage-runtime",
                "craft-launcher-host-tests-artifact",
                "craft-launcher-quit-state",
                "designcraft-appstream",
                "designcraft-cli",
                "designcraft-gui",
                "designcraft-host-tests-artifact",
                "designcraft-licenses",
                "designcraft-wayland",
                "effectcraft-host-tests-artifact",
                "figcraft-server",
            ],
        )
        for case in result.values():
            self.assertEqual(
                set(case["all"]),
                set(case["lint"])
                | set(case["manual"])
                | set(case["localOnly"])
                | set(case["native"])
                | set(case["application"]),
            )
            self.assertFalse(set(case["application"]) & set(case["native"]))
            self.assertFalse(set(case["lint"]) & set(case["native"]))
            self.assertFalse(set(case["manual"]) & set(case["native"]))
            self.assertFalse(set(case["localOnly"]) & set(case["native"]))


if __name__ == "__main__":
    unittest.main()
