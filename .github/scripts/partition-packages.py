"""Assign selected packages to balanced build shards."""

import argparse
import json
import math
import sys
from pathlib import Path


def positive_weight(value, name):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise TypeError(f"Weight for {name} must be numeric")
    weight = float(value)
    if not math.isfinite(weight) or weight <= 0:
        raise ValueError(f"Weight for {name} must be finite and positive")
    return weight


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, required=True)
    parser.add_argument("--index", type=int, required=True)
    parser.add_argument("--weights", type=Path, required=True)
    args = parser.parse_args()
    if args.count < 1 or not 0 <= args.index < args.count:
        parser.error("partition count or index is invalid")

    config = json.loads(args.weights.read_text(encoding="utf-8"))
    if not isinstance(config, dict) or not isinstance(config.get("weights", {}), dict):
        parser.error("weights file must contain an object with a weights object")
    default = positive_weight(config.get("default", 1), "default")
    weights = {
        name: positive_weight(value, name)
        for name, value in config.get("weights", {}).items()
    }
    names = sys.stdin.read().splitlines()
    if len(names) != len(set(names)) or any(not name for name in names):
        parser.error("package names must be nonempty and unique")

    # The shared CI check partitioner uses the same deterministic greedy rule.
    partitions = [[] for _ in range(args.count)]
    loads = [0.0] * args.count
    for name in sorted(names, key=lambda item: (-weights.get(item, default), item)):
        shard = min(
            range(args.count),
            key=lambda candidate: (
                loads[candidate],
                len(partitions[candidate]),
                candidate,
            ),
        )
        partitions[shard].append(name)
        loads[shard] += weights.get(name, default)

    # Reverse package shard order so the most expensive check and package start
    # on separate runners, while still balancing new work by its weight.
    selected = partitions[args.count - 1 - args.index]
    if selected:
        sys.stdout.write("\n".join(sorted(selected)) + "\n")


if __name__ == "__main__":
    main()
