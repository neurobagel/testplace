"""Propose conventional-commit titles for upstream commits since each tool's last tag.

Usage (from monorepo-migration/migration/):
  uv run --no-project --quiet --with pyyaml==6.0.3 python gen-commit-rewrites.py <scratch-dir>

For every tool package in names.yaml: clone (blobless) into <scratch-dir>, list the
commits on the default branch since the latest tag reachable from it, and for each
commit whose title is not a conventional commit, derive a type from the labels of the
PR named in the title "(#N)" (GitHub API via `gh api`).

Writes commit-rewrites.yaml. Entries already present in the file (same repo and sha)
are kept unchanged, so maintainer resolutions survive reruns. Entries that cannot be
derived get `new: null` and an `unclear:` reason; import.sh refuses to run until every
entry has a `new` title.
"""

import json
import os
import re
import subprocess
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
NAMES = os.path.join(HERE, "names.yaml")
OUT = os.path.join(HERE, "commit-rewrites.yaml")

CONVENTIONAL = re.compile(
    r"^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert|deps)(\([^)]*\))?!?: "
)
PR_NUMBER = re.compile(r"\(#(\d+)\)\s*$")
BRACKET_PREFIX = re.compile(r"^(\[[^\]]+\]\s*)+")

# Upstream release labels (auto, .autorc) -> conventional type. First matching label wins.
# None = cannot be derived without a maintainer decision.
LABEL_RULES = [
    ("pr-major-breaking", "feat!"),
    ("pr-minor-breaking", "feat!"),
    ("pr-minor", "feat"),
    ("pr-patch", "fix"),
    ("pr-bug-fix", "fix"),
    ("pr-performance", "perf"),
    ("pr-internal", "chore"),  # maintainer decision, Gate 2 (2026-11-09)
    ("pr-documentation", "docs"),
    ("pr-tests", "test"),
    ("pr-dependencies", "build(deps)"),
    ("skip-release", "chore"),
    ("dependencies", "build(deps)"),
    ("_bot", "chore"),
]
NOTES = {
    "pr-minor-breaking": "upstream: breaking, minor bump; release-please uses bump-minor-pre-major: true (Gate 2)",
    "pr-major-breaking": "upstream: breaking, major bump",
}
UNCLEAR = {}


def run(*cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True).stdout


def pr_labels(org, repo, number):
    out = run("gh", "api", f"repos/{org}/{repo}/issues/{number}", "--jq", "[.labels[].name]")
    return json.loads(out)


def propose(title, labels):
    rest = BRACKET_PREFIX.sub("", title).strip()
    for label, ctype in LABEL_RULES:
        if label in labels:
            if ctype is None:
                return None, label, UNCLEAR.get(label, f"no rule for label {label}"), None
            return f"{ctype}: {rest}", label, None, NOTES.get(label)
    return None, None, f"no release label among {labels}", None


def main(scratch):
    names = yaml.safe_load(open(NAMES, encoding="utf-8"))
    org = names["org"]
    existing = {}
    if os.path.exists(OUT):
        existing = yaml.safe_load(open(OUT, encoding="utf-8")) or {}

    result = {}
    unclear_count = 0
    os.makedirs(scratch, exist_ok=True)
    for pkg in names["packages"]:
        repo = pkg["repo"]
        clone = os.path.join(scratch, repo)
        if os.path.isdir(clone):
            run("git", "fetch", "-q", "--tags", "origin", cwd=clone)
            run("git", "reset", "-q", "--soft", "origin/HEAD", cwd=clone)
        else:
            run("git", "clone", "-q", "--filter=blob:none", "--no-checkout",
                f"https://github.com/{org}/{repo}.git", clone)
        head = run("git", "rev-parse", "origin/HEAD", cwd=clone).strip()
        last_tag = run("git", "describe", "--tags", "--abbrev=0", head, cwd=clone).strip()
        log = run("git", "log", "--format=%H%x09%an%x09%s", f"{last_tag}..{head}", cwd=clone)

        kept = {c["sha"]: c for c in (existing.get(repo) or {}).get("commits") or []}
        commits = []
        for line in log.splitlines():
            sha, author, title = line.split("\t", 2)
            if CONVENTIONAL.match(title):
                continue
            if sha in kept:
                commits.append(kept[sha])
                if not kept[sha].get("new"):
                    unclear_count += 1
                continue
            m = PR_NUMBER.search(title)
            entry = {"sha": sha, "author": author, "old": title}
            if not m:
                entry.update({"pr": None, "labels": [], "rule": None, "new": None,
                              "unclear": "no PR number in title"})
            else:
                number = int(m.group(1))
                labels = pr_labels(org, repo, number)
                new, rule, unclear, note = propose(title, labels)
                entry.update({"pr": number, "labels": labels, "rule": rule, "new": new})
                if unclear:
                    entry["unclear"] = unclear
                if note:
                    entry["note"] = note
            if not entry["new"]:
                unclear_count += 1
            commits.append(entry)
        result[repo] = {"last_tag": last_tag, "head": head, "commits": commits}
        print(f"{repo}: {last_tag}..{head[:7]}: {len(commits)} non-conventional titles", file=sys.stderr)

    header = (
        "# Commit title rewrites applied by import.sh (first line of the commit message only).\n"
        "# Generated by gen-commit-rewrites.py from PR release labels; reviewed by a maintainer.\n"
        "# Scope: commits since each tool's last tag whose titles are not conventional commits.\n"
        "# Existing entries are kept on regeneration. Entries with `new: null` must be resolved\n"
        "# (set `new`, and record `resolved_by`) before import.sh will run.\n"
    )
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(header)
        yaml.safe_dump(result, f, sort_keys=False, allow_unicode=True, width=1000)
    print(f"wrote {OUT}; unresolved: {unclear_count}", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
