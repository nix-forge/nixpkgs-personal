"""Plan native checks and affected package builds before assigning runners."""

import json
import math
import os
import re
import subprocess  # ruff: ignore[suspicious-subprocess-import] -- Fixed local Git and Nix commands, without a shell.
import sys
from pathlib import Path

RUNNERS = {
    "x86_64-linux": "ubuntu-24.04",
    "aarch64-linux": "ubuntu-24.04-arm",
    "aarch64-darwin": "macos-26",
}
LINUX_LEGACY_LABELS = {0: "2/2", 1: "1/6"}
SHARED_PATHS = re.compile(
    r"^(?:(?:flake\.nix|flake\.lock|pkgs/default\.nix|\.github/ci-policy\.json)$"
    r"|flake/|lib/|scripts/|\.github/(?:scripts|tests|workflows)/)"
)
PACKAGE_PATH = re.compile(r"^pkgs/by-name/[^/]+/([^/]+)/")
PACKAGE_NAME = re.compile(r"[a-z0-9][a-z0-9+._-]*")


def positive_weight(value, name):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise TypeError(f"Weight for {name} must be numeric")
    weight = float(value)
    if not math.isfinite(weight) or weight <= 0:
        raise ValueError(f"Weight for {name} must be finite and positive")
    return weight


def git(*args):
    return subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true]
        ["git", *args],  # ruff: ignore[start-process-with-partial-path]
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def changed_packages(base):
    if not re.fullmatch(r"[0-9a-f]{40}", base) or not base.strip("0"):
        return "", None
    try:
        paths = git(
            "diff", "--no-renames", "--name-only", "-z", base, "HEAD", "--"
        ).split("\0")
    except subprocess.CalledProcessError:
        return "", None
    if any(SHARED_PATHS.match(path) for path in paths):
        return base, None
    return base, {match[1] for path in paths if (match := PACKAGE_PATH.match(path))}


def exclusions():
    policy = json.loads(Path(".github/ci-policy.json").read_text(encoding="utf-8"))
    if not isinstance(policy, dict):
        raise TypeError("Hosted build policy must be an object")
    for package, reason in policy.items():
        if (
            not PACKAGE_NAME.fullmatch(package)
            or not isinstance(reason, str)
            or not reason.strip()
        ):
            raise ValueError(f"Invalid hosted build exclusion for {package}")
        if not (Path("pkgs/by-name") / package[:2] / package / "package.nix").is_file():
            raise ValueError(
                f"Hosted build exclusion names an unknown package: {package}"
            )
    return set(policy)


def package_names(system):
    result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true]
        [  # ruff: ignore[start-process-with-partial-path]
            "nix",
            "eval",
            "--no-write-lock-file",
            "--option",
            "allow-import-from-derivation",
            "false",
            "--json",
            f".#packages.{system}",
            "--apply",
            "builtins.attrNames",
        ],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    return set(json.loads(result.stdout))


def partition(names, default, weights):
    count = min(6, max(1, len(names)))
    # The shared CI check partitioner uses the same deterministic greedy rule.
    partitions = [[] for _ in range(count)]
    loads = [0.0] * count
    for name in sorted(names, key=lambda item: (-weights.get(item, default), item)):
        shard = min(
            range(count),
            key=lambda candidate: (
                loads[candidate],
                len(partitions[candidate]),
                candidate,
            ),
        )
        partitions[shard].append(name)
        loads[shard] += weights.get(name, default)

    # On broader updates, pair the native checks with the lightest shard.
    return [sorted(shard) for shard in reversed(partitions)]


def main():
    config = json.loads(
        Path(".github/ci-package-weights.json").read_text(encoding="utf-8")
    )
    if not isinstance(config, dict) or not isinstance(config.get("weights", {}), dict):
        raise TypeError("Weights file must contain an object with a weights object")
    default = positive_weight(config.get("default", 1), "default")
    weights = {
        name: positive_weight(value, name)
        for name, value in config.get("weights", {}).items()
    }
    excluded = exclusions()
    base, changed = changed_packages(os.environ.get("BASE_SHA", ""))
    if not base:
        sys.stderr.write(
            "::notice::Base history unavailable; validating all hosted packages.\n"
        )
    entries = []
    for system, runner in RUNNERS.items():
        available = package_names(system) if changed is None or changed else set()
        selected = available if changed is None else available & changed
        shards = partition(selected - excluded, default, weights)
        for index, packages in enumerate(shards):
            # Both Linux 2/2 names are required by the existing repository rules.
            label = f"{index + 1}/6"
            if system.endswith("-linux"):
                label = LINUX_LEGACY_LABELS.get(index, label)
            entries.append({
                "system": system,
                "runner": runner,
                "name": f"Build ({system} {label})",
                "native-checks": index == 0,
                "packages": json.dumps(packages, separators=(",", ":")),
            })
    matrix = json.dumps({"include": entries}, separators=(",", ":"))
    sys.stdout.write(f"matrix={matrix}\nbase-sha={base}\n")


if __name__ == "__main__":
    main()
