"""Helper for import.sh and verify.sh.

Run through uv so dependencies are pinned, e.g.:
  uv run --no-project --quiet --with pyyaml==6.0.3 --with git-filter-repo==2.47.0 \
      python import_helper.py <command> ...

Commands:
  names <names.yaml>
      Print names.yaml as tab-separated lines for shell scripts:
        org <org>
        pkg <repo> <dir> <tag_prefix>
        symlink <dir> <path-in-package> <data-dir>
        submodule <dir> <path-in-package>
        data <data-dir> <repo> <ref>
  filter <clone> <org> <repo> <dir> <tag_prefix> <commit-rewrites.yaml> <stats-out>
      Rewrite a fresh clone in place with git filter-repo:
        - move all files to packages/<dir>/
        - prefix all tags with <tag_prefix>-
        - replace the first line of commits listed in commit-rewrites.yaml
        - qualify GitHub references #N as <org>/<repo>#N in commit messages
      Writes rewrite statistics (JSON) to <stats-out>.
  relpath <from-dir> <to-path>
      Print the relative path from <from-dir> to <to-path> (both relative to the repo root).
"""

import json
import os
import re
import sys

import yaml


def load_yaml(path):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def cmd_names(path):
    names = load_yaml(path)
    print(f"org\t{names['org']}")
    for p in names["packages"]:
        print(f"pkg\t{p['repo']}\t{p['dir']}\t{p['tag_prefix']}")
        for sub_path, data_dir in (p.get("symlinks") or {}).items():
            print(f"symlink\t{p['dir']}\t{sub_path}\t{data_dir}")
        for sub_path in p.get("submodules") or []:
            print(f"submodule\t{p['dir']}\t{sub_path}")
    for data_dir, d in names["data"].items():
        print(f"data\t{data_dir}\t{d['repo']}\t{d['ref']}")


# A GitHub autolink reference "#123" that is not already qualified ("org/repo#123"),
# not part of a word ("abc#1"), a URL fragment ("/#1"), or an HTML entity ("&#123;").
REF_RE = re.compile(rb"(?<![\w/.&-])#(\d+)\b")


def load_title_rewrites(path, repo):
    """Return {original full sha (bytes): new title (bytes)} for one repo."""
    data = load_yaml(path)
    entry = data.get(repo) or {}
    rewrites = {}
    for c in entry.get("commits") or []:
        new = c.get("new")
        if not new:
            if os.environ.get("IMPORT_ALLOW_UNRESOLVED") == "1":
                print(f"WARNING: {repo} {c['sha'][:12]} unresolved, title left unchanged", file=sys.stderr)
                continue
            sys.exit(f"commit-rewrites.yaml: {repo} {c['sha']} has no resolved 'new' title")
        rewrites[c["sha"].encode()] = new.encode("utf-8")
    return rewrites


def cmd_filter(clone, org, repo, pkg_dir, tag_prefix, rewrites_path, stats_out):
    import git_filter_repo as fr

    rewrites = load_title_rewrites(rewrites_path, repo)
    qualified = f"{org}/{repo}#".encode()
    stats = {
        "repo": repo,
        "commits": 0,
        "titles_rewritten": 0,
        "messages_with_refs": 0,
        "refs_qualified": 0,
        "refs_parenthesized": 0,
    }
    applied = set()

    def commit_callback(commit, _metadata):
        stats["commits"] += 1
        msg = commit.message
        new_title = rewrites.get(commit.original_id)
        if new_title is not None:
            first, sep, rest = msg.partition(b"\n")
            msg = new_title + sep + rest
            stats["titles_rewritten"] += 1
            applied.add(commit.original_id)
        refs = REF_RE.findall(msg)
        if refs:
            stats["messages_with_refs"] += 1
            stats["refs_qualified"] += len(refs)
            stats["refs_parenthesized"] += len(re.findall(rb"\(#\d+\)", msg))
            msg = REF_RE.sub(qualified + rb"\1", msg)
        commit.message = msg

    os.chdir(clone)
    args = fr.FilteringOptions.parse_args(
        [
            "--to-subdirectory-filter", f"packages/{pkg_dir}",
            "--tag-rename", f":{tag_prefix}-",
            "--quiet",
        ]
    )
    fr.RepoFilter(args, commit_callback=commit_callback).run()

    missing = set(rewrites) - applied
    if missing:
        sys.exit(
            f"commit-rewrites.yaml: {repo}: {len(missing)} listed commits not found: "
            + ", ".join(sorted(m.decode()[:12] for m in missing))
        )
    with open(stats_out, "w", encoding="utf-8") as f:
        json.dump(stats, f, indent=2)
        f.write("\n")


def cmd_relpath(from_dir, to_path):
    print(os.path.relpath(to_path, from_dir))


def main(argv):
    if not argv:
        sys.exit(__doc__)
    cmd, args = argv[0], argv[1:]
    if cmd == "names" and len(args) == 1:
        cmd_names(*args)
    elif cmd == "filter" and len(args) == 7:
        cmd_filter(*args)
    elif cmd == "relpath" and len(args) == 2:
        cmd_relpath(*args)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
