#!/usr/bin/env python3
"""Copy the shared configs in shared/ into the tool folders, as listed in shared/files.yaml.

Usage (from anywhere in the repository; needs PyYAML):
  sync-shared.py           write every copy that differs from its source; exit 1 if any did
  sync-shared.py --check   only report copies that differ; exit 1 if any do

Runs as a commit hook (root .pre-commit-config.yaml): a commit that changes a source
gets its copies updated, to be added to the commit. A copy edited by hand is overwritten.
"""

import argparse
import os
import subprocess
import sys

import yaml


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="report differences, write nothing")
    opts = ap.parse_args()

    root = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                          check=True).stdout.strip()
    with open(os.path.join(root, "shared", "files.yaml"), encoding="utf-8") as f:
        entries = yaml.safe_load(f) or []

    problems, changed = [], []
    for entry in entries:
        source = entry["source"]
        if not source.startswith("shared/"):
            problems.append(f"{source}: sources must be in shared/")
            continue
        try:
            with open(os.path.join(root, source), "rb") as f:
                content = f.read()
        except FileNotFoundError:
            problems.append(f"{source}: missing")
            continue
        for copy in entry.get("copies") or []:
            if not copy.startswith("tools/"):
                problems.append(f"{copy}: copies must be inside a tool folder")
                continue
            path = os.path.join(root, copy)
            current = open(path, "rb").read() if os.path.exists(path) else None
            if current == content:
                continue
            changed.append(copy)
            if not opts.check:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "wb") as f:
                    f.write(content)

    for p in problems:
        print(f"error: {p}")
    verb = "differs from" if opts.check else "updated from"
    for c in changed:
        print(f"{c}: {verb} its source in shared/")
    return 1 if problems or changed else 0


if __name__ == "__main__":
    sys.exit(main())
