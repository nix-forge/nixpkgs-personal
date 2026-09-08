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
                        native = builtins.attrNames module.flake.ciChecks.test-system;
                    };
            in {
                before = inspect { first = null; } {};
                added = inspect { first = null; new-check = null; } {};
                removed = inspect { new-check = null; } {};
                newOwner = inspect { first = null; } { new-lint-check = null; };
            }
        """.replace("MODULE", json.dumps(str(MODULE)))
        result = json.loads(
            subprocess.check_output(
                ["nix", "eval", "--impure", "--json", "--expr", expression], text=True
            )
        )
        self.assertEqual(result["before"]["native"], ["first"])
        self.assertEqual(result["added"]["native"], ["first", "new-check"])
        self.assertEqual(result["removed"]["native"], ["new-check"])
        self.assertIn("new-lint-check", result["newOwner"]["lint"])
        self.assertNotIn("new-lint-check", result["newOwner"]["native"])
        for case in result.values():
            self.assertEqual(set(case["all"]), set(case["lint"]) | set(case["native"]))
            self.assertFalse(set(case["lint"]) & set(case["native"]))


if __name__ == "__main__":
    unittest.main()
