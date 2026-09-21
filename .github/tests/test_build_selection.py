"""Exercise the workflow's package selection with real Git and Nix evaluation."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "build-affected.sh"
RETRY = SCRIPT.with_name("build-with-fetch-retry.sh")
PARTITION = SCRIPT.with_name("partition-packages.py")
WEIGHTS = SCRIPT.parents[1] / "ci-package-weights.json"


def command(args, root):
    return subprocess.check_output(args, cwd=root, text=True).strip()


def commit(root):
    command(["git", "add", "."], root)
    command(["git", "-c", "commit.gpgsign=false", "commit", "-qm", "fixture"], root)
    return command(["git", "rev-parse", "HEAD"], root)


def package(path, name, version="1", description="before"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        'let drv = builtins.derivation { name = "'
        + name
        + "-"
        + version
        + '"; system = "x86_64-linux"; builder = "/bin/sh"; }; '
        + 'in drv // { meta.description = "'
        + description
        + '"; }\n'
    )


def flake(root, name, empty=False, invalid=False):
    text = (
        "{ outputs = { self }: { packages.x86_64-linux = { "
        + (
            ""
            if empty
            else name
            + " = import ./pkgs/by-name/"
            + name[:2]
            + "/"
            + name
            + "/package.nix; "
        )
        + "other = import ./other.nix; }; }; }\n"
    )
    (root / "flake.nix").write_text("invalid nix syntax !!!" if invalid else text)


class BuildSelectionTests(unittest.TestCase):
    def test_weighted_partition_scales_with_new_packages(self):
        names = ["maintainerr", "alpha", "beta", "gamma", "future"]
        for count in (1, 2, 3):
            shards = []
            for index in range(count):
                result = subprocess.run(
                    [
                        "python3",
                        str(PARTITION),
                        "--count",
                        str(count),
                        "--index",
                        str(index),
                        "--weights",
                        str(WEIGHTS),
                    ],
                    input="\n".join(names),
                    text=True,
                    capture_output=True,
                    check=True,
                )
                shards.append(result.stdout.splitlines())
            self.assertEqual(
                sorted(name for shard in shards for name in shard), sorted(names)
            )
            self.assertEqual(
                len({name for shard in shards for name in shard}), len(names)
            )
            self.assertEqual(
                shards[-1], ["maintainerr"] if count > 1 else sorted(names)
            )

    def test_real_evaluation(self):
        real_nix = shutil.which("nix")
        real_git = shutil.which("git")
        if real_nix is None or real_git is None:
            raise RuntimeError(
                "Nix and Git are required for build-selection regression tests"
            )
        cases = [
            "metadata",
            "runtime-change",
            "registry-change",
            "infrastructure-script",
            "infrastructure-test",
            "infrastructure-workflow",
            "new-package",
            "base-eval-failure",
            "no-base",
            "partitioned-maintainerr",
            "zero-base",
            "missing-base",
            "diff-failure",
            "unchanged-contracts",
            "current-eval-failure",
            "evaluation-only",
            "unknown-policy-package",
            "blank-policy-reason",
            "missing-policy",
            "malformed-policy",
            "invalid-policy-reason",
            "other-platform-policy",
        ]
        for case in cases:
            with (
                self.subTest(case=case),
                tempfile.TemporaryDirectory(prefix="ci-build-selection-") as temp_dir,
            ):
                temp = Path(temp_dir)
                root = temp / "repo"
                root.mkdir()
                helper = root / ".github/scripts/build-with-fetch-retry.sh"
                helper.parent.mkdir(parents=True)
                helper.write_text(RETRY.read_text())
                (helper.parent / PARTITION.name).write_text(PARTITION.read_text())
                (helper.parents[1] / WEIGHTS.name).write_text(WEIGHTS.read_text())
                policy = root / ".github/ci-policy.json"
                policy.write_text(
                    '{"demo": "Evaluation only: fixture restriction"}'
                    if case == "evaluation-only"
                    else "{}"
                )
                command(["git", "init", "-q", "-b", "main"], root)
                command(["git", "config", "user.name", "CI Test"], root)
                command(["git", "config", "user.email", "ci@example.invalid"], root)
                command(["git", "config", "core.hooksPath", "/dev/null"], root)
                name = (
                    "openai-codex-desktop"
                    if case == "unchanged-contracts"
                    else "maintainerr"
                    if case == "partitioned-maintainerr"
                    else "demo"
                )
                source = root / "pkgs/by-name" / name[:2] / name / "package.nix"
                package(source, name)
                package(root / "other.nix", "other")
                if case == "unknown-policy-package":
                    policy.write_text('{"demoo": "Evaluation only: typo"}')
                elif case == "blank-policy-reason":
                    policy.write_text('{"demo": "   "}')
                elif case == "missing-policy":
                    policy.unlink()
                elif case == "malformed-policy":
                    policy.write_text('{"demo":')
                elif case == "invalid-policy-reason":
                    policy.write_text('{"demo": null}')
                elif case == "other-platform-policy":
                    policy.write_text(
                        '{"foreign": "Evaluation only: another platform"}'
                    )
                    package(root / "pkgs/by-name/fo/foreign/package.nix", "foreign")
                flake(
                    root,
                    name,
                    empty=case == "new-package",
                    invalid=case == "base-eval-failure",
                )
                if case == "registry-change":
                    registry = root / "flake/dev/packages.nix"
                    package(registry, "other")
                    entry = root / "flake.nix"
                    entry.write_text(
                        entry.read_text().replace(
                            "./other.nix", "./flake/dev/packages.nix"
                        )
                    )
                base = commit(root)
                package(
                    source,
                    name,
                    version="2"
                    if case
                    in {
                        "runtime-change",
                        "evaluation-only",
                        "unknown-policy-package",
                        "blank-policy-reason",
                        "missing-policy",
                        "malformed-policy",
                        "invalid-policy-reason",
                    }
                    else "1",
                    description="after",
                )
                flake(root, name, invalid=case == "current-eval-failure")
                if case == "registry-change":
                    package(registry, "other", version="2")
                    entry.write_text(
                        entry.read_text().replace(
                            "./other.nix", "./flake/dev/packages.nix"
                        )
                    )
                infrastructure = {
                    "infrastructure-script": ".github/scripts/fixture.sh",
                    "infrastructure-test": ".github/tests/test_fixture.py",
                    "infrastructure-workflow": ".github/workflows/fixture.yml",
                }
                if case in infrastructure:
                    changed = root / infrastructure[case]
                    changed.parent.mkdir(parents=True, exist_ok=True)
                    changed.write_text("# Check infrastructure changed\n")
                commit(root)
                bindir = temp / "bin"
                bindir.mkdir()
                nix = bindir / "nix"
                nix.write_text("""#!/usr/bin/env bash
set -eu
if [[ "$1" == build ]]; then
    printf '%s\\n' "$*" >> "$BUILD_LOG"
    exit 0
fi
exec "$REAL_NIX" "$@"
""")
                nix.chmod(0o755)
                git = bindir / "git"
                git.write_text("""#!/usr/bin/env bash
set -eu
if [[ "$1" == diff && "$TEST_CASE" == diff-failure ]]; then
    exit 128
fi
exec "$REAL_GIT" "$@"
""")
                git.chmod(0o755)
                log = temp / "build.log"
                if case in {"no-base", "partitioned-maintainerr"}:
                    base = ""
                elif case == "zero-base":
                    base = "0" * 40
                elif case == "missing-base":
                    base = "f" * 40
                    self.assertNotEqual(
                        subprocess.run(
                            ["git", "cat-file", "-e", base],
                            cwd=root,
                            capture_output=True,
                        ).returncode,
                        0,
                    )
                env = os.environ | {
                    "PATH": str(bindir) + ":" + os.environ["PATH"],
                    "REAL_NIX": real_nix,
                    "REAL_GIT": real_git,
                    "TEST_CASE": case,
                    "BUILD_LOG": str(log),
                    "BASE_SHA": base,
                    "SYSTEM": "x86_64-linux",
                }
                result = subprocess.run(
                    ["bash", str(SCRIPT)],
                    cwd=root,
                    env=env,
                    text=True,
                    capture_output=True,
                )
                builds = log.read_text().splitlines() if log.exists() else []
                if case in {
                    "current-eval-failure",
                    "unknown-policy-package",
                    "blank-policy-reason",
                    "missing-policy",
                    "malformed-policy",
                    "invalid-policy-reason",
                }:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(builds, [])
                    if case != "current-eval-failure":
                        self.assertIn("policy", result.stdout.lower())
                    continue
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                if case == "evaluation-only":
                    self.assertEqual(builds, [])
                    self.assertIn("fixture restriction", result.stdout)
                elif case in {"metadata", "other-platform-policy"}:
                    self.assertEqual(builds, [])
                    self.assertIn("unchanged derivation", result.stdout)
                elif case.startswith("infrastructure-"):
                    self.assertEqual(builds, [])
                    self.assertIn("demo: unchanged derivation", result.stdout)
                    self.assertIn("other: unchanged derivation", result.stdout)
                elif case == "registry-change":
                    self.assertEqual(len(builds), 1, builds)
                    self.assertIn(".#other", builds[0])
                elif case == "unchanged-contracts":
                    self.assertEqual(len(builds), 1, builds)
                    self.assertIn(
                        "checks.x86_64-linux.openai-codex-desktop-updater", builds[0]
                    )
                    self.assertIn(
                        "checks.x86_64-linux.openai-codex-desktop-package-contract",
                        builds[0],
                    )
                else:
                    full_rebuild = case in {
                        "base-eval-failure",
                        "no-base",
                        "partitioned-maintainerr",
                        "zero-base",
                        "missing-base",
                        "diff-failure",
                    }
                    self.assertEqual(len(builds), 2 if full_rebuild else 1, builds)
                    self.assertIn(f".#{name}", builds[0])
                    if full_rebuild:
                        self.assertIn(".#other", builds[1])
                        self.assertIn("unavailable", result.stdout)
                if case in {"no-base", "partitioned-maintainerr"}:
                    partition_builds = []
                    for index in (0, 1):
                        log.unlink()
                        partition_result = subprocess.run(
                            ["bash", str(SCRIPT)],
                            cwd=root,
                            env=env
                            | {"PARTITION_COUNT": "2", "PARTITION_INDEX": str(index)},
                            text=True,
                            capture_output=True,
                        )
                        self.assertEqual(
                            partition_result.returncode,
                            0,
                            partition_result.stdout + partition_result.stderr,
                        )
                        partition_builds.append(
                            log.read_text().splitlines() if log.exists() else []
                        )
                    self.assertEqual(
                        sorted(partition_builds[0] + partition_builds[1]),
                        sorted(builds),
                    )
                    self.assertFalse(
                        set(partition_builds[0]) & set(partition_builds[1])
                    )
                    if case == "partitioned-maintainerr":
                        self.assertEqual(len(partition_builds[1]), 1)
                        self.assertIn(".#maintainerr", partition_builds[1][0])


if __name__ == "__main__":
    unittest.main()
