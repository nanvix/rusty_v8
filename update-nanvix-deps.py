#!/usr/bin/env python3
"""Update Nanvix patched dependencies to latest branch heads."""

from __future__ import annotations

import argparse
import os
import pathlib
import subprocess
import sys
from typing import Iterable, List

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:  # pragma: no cover
    import tomli as tomllib  # type: ignore


def load_patched_specs(config_path: pathlib.Path, names: Iterable[str]) -> List[str]:
    """Return cargo package specs (name@version) derived from patch branches."""
    data = tomllib.loads(config_path.read_text(encoding="utf-8"))
    patches = data.get("patch", {}).get("crates-io", {})
    specs: List[str] = []

    for name in names:
        entry = patches.get(name)
        if not entry:
            print(f"Warning: {name} missing from [patch.crates-io]", file=sys.stderr)
            continue

        branch = str(entry.get("branch", ""))
        version_token = branch.rsplit("/", 1)[-1] if branch else ""
        if version_token.startswith("v"):
            version_token = version_token[1:]

        if not version_token:
            print(
                f"Warning: Could not derive version for {name} from branch '{branch}'",
                file=sys.stderr,
            )
            continue

        specs.append(f"{name}@{version_token}")

    return specs


def run_cargo_updates(specs: Iterable[str]) -> None:
    """Invoke `cargo update` for each fully qualified spec."""
    for spec in specs:
        print(f"Updating {spec}…")
        subprocess.run(["cargo", "update", "-p", spec], check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config",
        default=".cargo/config.toml",
        type=pathlib.Path,
        help="Path to the cargo config containing [patch.crates-io] overrides.",
    )
    parser.add_argument(
        "--deps",
        default=os.environ.get("PATCHED_DEPS", ""),
        help="Space-separated list of dependency names to refresh.",
    )
    args = parser.parse_args()

    if not args.deps:
        print("No dependencies provided via --deps or PATCHED_DEPS", file=sys.stderr)
        return 1

    config_path = args.config
    if not config_path.exists():
        print(f"Config file {config_path} not found", file=sys.stderr)
        return 1

    specs = load_patched_specs(config_path, args.deps.split())
    if not specs:
        print("No dependency specs could be derived", file=sys.stderr)
        return 1

    run_cargo_updates(specs)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
