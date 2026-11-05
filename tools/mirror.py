#!/usr/bin/env python3
"""Mirror monorepo folders to the old per-tool repositories, through pull requests.

During the monorepo trial the old repositories are read-only mirrors (see DEVELOPING.md,
"The old repositories"). For each old repository this script:

1. Extends the branch `monorepo-mirror` with one commit per monorepo commit (main,
   first-parent) that changes the folder's content. Each commit holds the folder as it is
   in the monorepo, with one change: the shared-data symlinks listed in names.yaml become
   gitlinks to the data repository's mirror commit. Author, date and message are kept;
   `#N` becomes `<monorepo>#N`, and a `Monorepo-Commit: <monorepo>@<sha>` trailer is added.
   The branch starts at the old repository's commit that was imported (import-sources.txt).
2. Opens or updates one pull request `monorepo-mirror` -> main (a draft while the old
   repository is not locked).
3. Once the old CI on the branch passes, fast-forwards main to the branch and pushes the
   new tags (`<prefix>-vX.Y.Z` in the monorepo becomes `vX.Y.Z`). Only with --allow-merge
   (set by hand after switchover: repository variable MIRROR_MERGE=true) AND only in old
   repositories that are locked (a ruleset restricts updates of main). Otherwise the
   mirror writes nothing but the branch and a draft pull request.
4. Reports the old CI result as a commit status `mirror/<repo>` on the monorepo commit,
   and keeps one issue per repository open while it is red.

Data repositories (deploy/, testdata/) are processed first, so tool gitlinks can point
at their mirror commits. Reruns are safe: everything is derived from the branch.

Usage (from a full clone of the monorepo; needs PyYAML):
  mirror.py [--dry-run] [--reset] [--adopt REPO=SHA ...] [--allow-merge]
            [--github] [--assume-locked] [--assume-green] [--remote-template T]
  mirror.py --check [REV]     check that every folder at REV can be mirrored

Environment: MIRROR_TOKEN (old repositories), GH_TOKEN (monorepo; statuses and issues).
"""

from __future__ import annotations

import argparse
import base64
import bisect
import json
import os
import posixpath
import re
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field

import yaml

BRANCH = "monorepo-mirror"
TRAILER = "Monorepo-Commit"
SYMLINK, GITLINK = "120000", "160000"


class MirrorError(Exception):
    pass


def run(cmd, *, input=None, env=None, check=True):
    r = subprocess.run(cmd, capture_output=True, text=True, input=input, env=env)
    if check and r.returncode:
        raise MirrorError(f"{' '.join(cmd[:3])} ...: {r.stderr.strip() or r.stdout.strip()}")
    return r.stdout.strip()


def git(*args, **kw):
    return run(["git", *args], **kw)


def is_ancestor(a, b):
    return subprocess.run(["git", "merge-base", "--is-ancestor", a, b]).returncode == 0


def gh(args, token, *, check=True, input=None):
    env = dict(os.environ, GH_TOKEN=token or "")
    return run(["gh", *args], env=env, check=check, input=input)


def summary(line=""):
    print(line)
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a") as f:
            f.write(line + "\n")


@dataclass
class Target:
    repo: str
    folder: str
    anchor_old: str
    links: dict = field(default_factory=dict)  # path in folder -> data folder
    prefix: str | None = None  # tag prefix (packages only)
    is_data: bool = False


def load_targets(names_path, sources_path):
    names = yaml.safe_load(open(names_path))
    org = names["org"]
    sources = {}
    for line in open(sources_path):
        if line.strip() and not line.startswith("#"):
            _, repo, sha = line.rstrip("\n").split("\t")
            sources[repo] = sha
    targets = []
    for folder, d in names["data"].items():
        targets.append(Target(d["repo"], folder, sources[f"{org}/{d['repo']}"], is_data=True))
    for p in names["packages"]:
        targets.append(Target(p["repo"], f"packages/{p['dir']}", sources[f"{org}/{p['repo']}"],
                              links=p.get("symlinks") or {}, prefix=p["tag_prefix"]))
    return org, targets


class Mono:
    """The monorepo: first-parent history of the source ref."""

    def __init__(self, ref, org, name):
        self.ref = git("rev-parse", ref)
        self.org = org
        self.name = name  # owner/name, for messages
        self.order = git("rev-list", "--first-parent", "--reverse", self.ref).split()
        self.idx = {c: i for i, c in enumerate(self.order)}

    def anchor(self, t):
        if t.is_data:
            pattern = f"^chore: add {t.folder}/ from {self.org}/{t.repo}@"
        else:
            pattern = f"^chore: import {self.org}/{t.repo} history into {t.folder}$"
        sha = git("log", "--first-parent", "--format=%H", "-n", "1", "--grep", pattern, self.ref)
        if not sha:
            raise MirrorError(f"no import commit for {t.repo} ({pattern!r})")
        return sha


class DataTips:
    """Mirror commit of each data repository as of a monorepo commit."""

    def __init__(self, mono):
        self.mono = mono
        self.points = {}  # data folder -> (sorted idx list, commits, anchor_old)

    def set(self, folder, anchor_old, chain):
        pts = sorted((self.mono.idx[m], c) for c, m in chain if m in self.mono.idx)
        self.points[folder] = ([i for i, _ in pts], [c for _, c in pts], anchor_old)

    def at(self, folder, commit):
        idxs, commits, anchor_old = self.points[folder]
        k = bisect.bisect_right(idxs, self.mono.idx[commit])
        return commits[k - 1] if k else anchor_old


def ls_tree(rev, path=None):
    out = git("ls-tree", "-r", "--full-tree", rev, *([path] if path else []))
    for line in out.splitlines():
        meta, p = line.split("\t", 1)
        mode, _, sha = meta.split()
        yield mode, sha, p


def mirrored_tree(commit, t, tips):
    """The folder at <commit> as the old repository holds it."""
    tree = git("rev-parse", f"{commit}:{t.folder}")
    if not t.links:
        return tree
    swaps = []
    for path, data in t.links.items():
        entry = git("ls-tree", commit, f"{t.folder}/{path}")
        if entry and entry.split()[0] == SYMLINK:
            swaps.append(f"{GITLINK} commit {tips.at(data, commit)}\t{path}\n")
    if not swaps:
        return tree
    with tempfile.TemporaryDirectory() as d:
        env = dict(os.environ, GIT_INDEX_FILE=os.path.join(d, "index"))
        git("read-tree", tree, env=env)
        git("update-index", "--index-info", input="".join(swaps), env=env)
        return git("write-tree", env=env)


def check_folder(rev, t):
    """Problems that would make the mirrored folder differ from what the old repo needs."""
    problems = []
    if not git("ls-tree", rev, t.folder):
        return [f"{t.folder} is missing"]
    for mode, sha, path in ls_tree(rev, t.folder):
        rel = path[len(t.folder) + 1:]
        if mode != SYMLINK:
            continue
        if rel in t.links:
            want = posixpath.relpath(t.links[rel], posixpath.join(t.folder, posixpath.dirname(rel)))
            got = git("cat-file", "-p", sha)
            if got != want:
                problems.append(f"{path} -> {got}, expected {want}")
            continue
        dest = posixpath.normpath(posixpath.join(posixpath.dirname(path), git("cat-file", "-p", sha)))
        if not (dest + "/").startswith(t.folder + "/"):
            problems.append(f"{path} links outside {t.folder}/ ({dest}) and is not in names.yaml")
    return problems


QUALIFY = re.compile(r"(?<![\w/.-])#(\d+)\b")


def mirror_message(commit, mono):
    msg = git("log", "-1", "--format=%B", commit)
    msg = QUALIFY.sub(lambda m: f"{mono.name}#{m.group(1)}", msg)
    return git("interpret-trailers", "--trailer", f"{TRAILER}: {mono.name}@{commit}", input=msg + "\n") + "\n"


def commit_like(commit, tree, parents, message):
    fmt = "%an%x00%ae%x00%ad%x00%cn%x00%ce%x00%cd"
    an, ae, ad, cn, ce, cd = git("log", "-1", f"--format={fmt}", "--date=raw", commit).split("\0")
    env = dict(os.environ, GIT_AUTHOR_NAME=an, GIT_AUTHOR_EMAIL=ae, GIT_AUTHOR_DATE=ad,
               GIT_COMMITTER_NAME=cn, GIT_COMMITTER_EMAIL=ce, GIT_COMMITTER_DATE=cd)
    args = ["commit-tree", tree]
    for p in parents:
        args += ["-p", p]
    return git(*args, input=message, env=env)


def chain_of(tip, base):
    """[(old commit, monorepo sha)] of the mirror commits in base..tip, oldest first."""
    out = git("log", "--first-parent", "--reverse", "--format=%H%x00%(trailers:key=" + TRAILER
              + ",valueonly,separator=%x01)%x02", f"{base}..{tip}")
    chain = []
    for rec in filter(None, (r.strip() for r in out.split("\x02"))):
        c, values = rec.split("\0")
        values = [v for v in values.split("\x01") if v]
        if not values:
            return None  # a commit the mirror did not make
        chain.append((c, values[-1].rsplit("@", 1)[-1]))
    return chain


class Remote:
    def __init__(self, template, owner):
        self.template, self.owner = template, owner

    def url(self, repo):
        return self.template.format(owner=self.owner, repo=repo)

    def heads(self, repo):
        out = git("ls-remote", self.url(repo), "refs/heads/main", f"refs/heads/{BRANCH}")
        return {ref.rsplit("/", 1)[-1] if ref.endswith("/main") else BRANCH: sha
                for sha, ref in (line.split("\t") for line in out.splitlines())}

    def tags(self, repo):
        out = git("ls-remote", "--tags", self.url(repo))
        tags = {}
        for sha, ref in (line.split("\t") for line in out.splitlines()):
            name = ref[len("refs/tags/"):]
            if name.endswith("^{}"):
                tags[name[:-3]] = sha  # peeled
            else:
                tags.setdefault(name, sha)
        return tags

    def fetch(self, repo, ref, local):
        git("fetch", "-q", "--no-tags", self.url(repo), f"+{ref}:{local}")

    def push(self, repo, refspecs):
        git("push", "-q", self.url(repo), *refspecs)


class GitHub:
    """Pull requests, lock state and checks in the old repositories; statuses and issues
    in the monorepo. Inactive (and replaced by --assume-* flags) without --github."""

    def __init__(self, enabled, owner, mono_name, assume_locked, assume_green, wait):
        self.enabled, self.owner, self.mono_name = enabled, owner, mono_name
        self.assume_locked, self.assume_green = assume_locked, assume_green
        self.old_token = os.environ.get("MIRROR_TOKEN", "")
        self.mono_token = os.environ.get("GH_TOKEN", "")
        self.deadline = time.time() + wait * 60

    def locked(self, repo):
        if not self.enabled:
            return self.assume_locked
        rules = json.loads(gh(["api", f"repos/{self.owner}/{repo}/rules/branches/main"], self.old_token))
        return any(r.get("type") == "update" for r in rules)

    def ensure_pr(self, repo, locked, title, body):
        if not self.enabled:
            return None
        r = f"{self.owner}/{repo}"
        prs = json.loads(gh(["pr", "list", "-R", r, "--head", BRANCH, "--state", "open",
                             "--json", "number,isDraft,url"], self.old_token))
        if not prs:
            args = ["pr", "create", "-R", r, "--head", BRANCH, "--base", "main", "--title", title, "--body", body]
            return gh(args + ([] if locked else ["--draft"]), self.old_token).splitlines()[-1]
        pr = prs[0]
        gh(["pr", "edit", "-R", r, str(pr["number"]), "--title", title, "--body", body], self.old_token)
        if locked and pr["isDraft"]:
            gh(["pr", "ready", "-R", r, str(pr["number"])], self.old_token)
        return pr["url"]

    def checks(self, repo, sha):
        """'success', 'failure' or 'pending' for the check runs on sha (waits up to the deadline)."""
        if not self.enabled:
            return "success" if self.assume_green else "failure"
        started = time.time()
        while True:
            runs = json.loads(gh(["api", f"repos/{self.owner}/{repo}/commits/{sha}/check-runs?per_page=100"],
                                 self.old_token))["check_runs"]
            done = [c for c in runs if c["status"] == "completed"]
            if runs and len(done) == len(runs):
                bad = [c["name"] for c in done if c["conclusion"] not in ("success", "skipped", "neutral")]
                return "failure" if bad else "success"
            if not runs and time.time() - started > 180:
                return "success"  # the repository runs no checks on pull requests
            if time.time() > self.deadline:
                return "pending"
            time.sleep(30)

    def report(self, repo, mono_sha, state, url):
        if not self.enabled:
            return
        gh(["api", f"repos/{self.mono_name}/statuses/{mono_sha}", "-f", f"state={state}",
            "-f", f"context=mirror/{repo}", "-f", f"target_url={url or ''}",
            "-f", f"description=old CI in {self.owner}/{repo}: {state}"], self.mono_token)
        title = f"Mirror: old CI failing in {self.owner}/{repo}"
        issues = json.loads(gh(["issue", "list", "-R", self.mono_name, "--state", "open", "--search",
                                f'"{title}" in:title', "--json", "number,title"], self.mono_token))
        issue = next((i["number"] for i in issues if i["title"] == title), None)
        if state == "failure":
            text = (f"The old CI fails on the mirror pull request {url}, for {self.mono_name}@{mono_sha}.\n\n"
                    "Fix it in the monorepo; the mirror merges once the checks pass.")
            if issue:
                gh(["issue", "comment", "-R", self.mono_name, str(issue), "--body", text], self.mono_token)
            else:
                gh(["issue", "create", "-R", self.mono_name, "--title", title, "--body", text], self.mono_token)
        elif state == "success" and issue:
            gh(["issue", "close", "-R", self.mono_name, str(issue), "--comment",
                f"Old CI passes again ({self.mono_name}@{mono_sha})."], self.mono_token)


def mirror_target(t, mono, tips, remote, hub, opts):
    """Sync one repository. Returns (old tip, chain, locked, heads)."""
    heads = remote.heads(t.repo)
    if "main" not in heads:
        raise MirrorError("no main branch")
    remote.fetch(t.repo, "refs/heads/main", f"refs/mirror/{t.repo}/main")
    old_main = heads["main"]
    # "locked" means: may merge and tag. Both the explicit switch and the ruleset are needed.
    locked = opts.allow_merge and hub.locked(t.repo)
    summary(f"  merging {'on' if locked else 'off'} (--allow-merge {'set' if opts.allow_merge else 'not set'})")
    mono_anchor = mono.anchor(t)
    if git("cat-file", "-t", t.anchor_old, check=False) != "commit":
        raise MirrorError(f"anchor {t.anchor_old} is not in the old main history")

    chain, tip, force = None, None, False
    if BRANCH in heads and not opts.reset:
        remote.fetch(t.repo, f"refs/heads/{BRANCH}", f"refs/mirror/{t.repo}/branch")
        tip = heads[BRANCH]
        if is_ancestor(t.anchor_old, tip):
            chain = chain_of(tip, t.anchor_old)
        usable = chain is not None and all(m in mono.idx for _, m in chain)
        if not usable:
            if locked:
                raise MirrorError(f"{BRANCH} does not continue this monorepo's history; rerun with reset")
            print(f"  {BRANCH} belongs to an earlier build: rebuilding it")
            chain, tip = None, None
    if chain is None:
        # Start at the anchor: the import must reproduce the old tree exactly.
        if mirrored_tree(mono_anchor, t, tips) != git("rev-parse", f"{t.anchor_old}^{{tree}}"):
            raise MirrorError(f"the monorepo at its import commit differs from {t.anchor_old}")
        chain, tip, force = [], t.anchor_old, BRANCH in heads

    last = chain[-1][1] if chain else mono_anchor
    adopt = opts.adopt.get(t.repo)
    if adopt:
        if adopt != old_main:
            raise MirrorError(f"adopt: main is at {old_main}, not {adopt}")
        msg = (f"chore: adopt {adopt[:12]} into the monorepo mirror\n\nCommits on main that did not come "
               f"from the mirror; their changes were ported to the monorepo.\n\n{TRAILER}: {mono.name}@{last}\n")
        tip = commit_like(last, git("rev-parse", f"{tip}^{{tree}}"), [tip, adopt], msg)
        chain.append((tip, last))

    new = []
    tree = git("rev-parse", f"{tip}^{{tree}}")
    for c in mono.order[mono.idx[last] + 1:]:
        t_tree = mirrored_tree(c, t, tips)
        if t_tree != tree:
            tip = commit_like(c, t_tree, [tip], mirror_message(c, mono))
            tree = t_tree
            chain.append((tip, c))
            new.append((tip, c))
    if t.is_data:
        tips.set(t.folder, t.anchor_old, chain)

    for _, c in new:
        summary(f"  + {git('log', '-1', '--format=%h %s', c)}")
    if not new and not adopt and not force:
        summary("  branch up to date")
    if not opts.dry_run and (new or adopt or force or BRANCH not in heads):
        remote.push(t.repo, [f"{'+' if force else ''}{tip}:refs/heads/{BRANCH}"])
    return tip, chain, locked, old_main


def merge_target(t, mono, remote, hub, opts, tip, chain, locked, old_main):
    """PR, checks, status; fast-forward and tags when locked and green."""
    if tip == old_main:
        summary("  main is at the branch: nothing to merge")
        state, url = "success", None
    else:
        head_mono = chain[-1][1] if chain else None
        title = f"Mirror of {mono.name} {t.folder}/ up to {head_mono[:12] if head_mono else 'the import'}"
        body = (f"Changes to `{t.folder}/` in {mono.name}, mirrored by tools/mirror.py.\n\n"
                + ("The mirror merges this pull request itself (fast-forward) once the checks pass."
                   if locked else "**Do not merge.** The monorepo is not switched over yet; this draft "
                   "only shows that the old CI passes on the mirrored code."))
        url = None if opts.dry_run else hub.ensure_pr(t.repo, locked, title, body)
        state = hub.checks(t.repo, tip) if not opts.dry_run else "pending"
        summary(f"  old CI: {state}{f' ({url})' if url else ''}")
        if state == "success" and locked and not opts.dry_run:
            if not is_ancestor(old_main, tip):
                raise MirrorError(f"main ({old_main[:12]}) has commits the mirror did not make: port them "
                                  "to the monorepo, then rerun with adopt")
            remote.push(t.repo, [f"{tip}:refs/heads/main"])
            summary("  main fast-forwarded")
            old_main = tip
    if chain and not opts.dry_run:
        hub.report(t.repo, chain[-1][1], state, url)
    if locked and t.prefix and old_main == tip and not opts.dry_run:
        push_tags(t, mono, remote, chain)


def push_tags(t, mono, remote, chain):
    mono_anchor = mono.idx[mono.anchor(t)]
    points = sorted((mono.idx[m], c) for c, m in chain if m in mono.idx)
    have = remote.tags(t.repo)
    refspecs = []
    for line in git("for-each-ref", "--format=%(refname:short) %(*objectname) %(objectname)",
                    f"refs/tags/{t.prefix}-v*").splitlines():
        name, *shas = line.split()
        commit = shas[0]
        i = mono.idx.get(commit)
        if i is None or i <= mono_anchor or not re.fullmatch(rf"{re.escape(t.prefix)}-v\d.*", name):
            continue
        old_name = name[len(t.prefix) + 1:]
        k = bisect.bisect_right([p for p, _ in points], i)
        target = points[k - 1][1] if k else t.anchor_old
        if old_name in have:
            if have[old_name] != target:
                raise MirrorError(f"tag {old_name} exists at {have[old_name][:12]}, expected {target[:12]}")
            continue
        refspecs.append(f"{target}:refs/tags/{old_name}")
        summary(f"  tag {old_name}")
    if refspecs:
        remote.push(t.repo, refspecs)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--names", default="migration/names.yaml")
    ap.add_argument("--sources", default="migration/import-sources.txt")
    ap.add_argument("--ref", default="main", help="monorepo ref to mirror (default main)")
    ap.add_argument("--monorepo", default=os.environ.get("GITHUB_REPOSITORY", "neurobagel/neurobagel"))
    ap.add_argument("--owner", default=os.environ.get("MIRROR_OWNER"), help="owner of the old repositories")
    ap.add_argument("--remote-template", default="https://github.com/{owner}/{repo}.git")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--reset", action="store_true", help="rebuild the mirror branches from the import")
    ap.add_argument("--adopt", nargs="*", default=[], metavar="REPO=SHA")
    ap.add_argument("--allow-merge", action="store_true",
                    help="fast-forward old main and push tags (only in locked repositories)")
    ap.add_argument("--github", action="store_true", help="pull requests, checks, statuses, issues")
    ap.add_argument("--assume-locked", action="store_true", help="without --github: treat repos as locked")
    ap.add_argument("--assume-green", action="store_true", help="without --github: treat old CI as passing")
    ap.add_argument("--wait-minutes", type=int, default=60)
    ap.add_argument("--check", nargs="?", const="HEAD", metavar="REV")
    opts = ap.parse_args()

    org, targets = load_targets(opts.names, opts.sources)
    if opts.check:
        problems = [p for t in targets for p in check_folder(opts.check, t)]
        for p in problems:
            print(f"::error::{p}")
        print(f"mirror check: {len(problems)} problem(s) in {len(targets)} folders")
        return 1 if problems else 0

    if not opts.owner:
        print("MIRROR_OWNER is not set: nothing to do")
        return 0
    token = os.environ.get("MIRROR_TOKEN")
    if token:  # authenticate git over HTTPS without putting the token in URLs
        basic = base64.b64encode(f"x-access-token:{token}".encode()).decode()
        os.environ.update(GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="http.https://github.com/.extraheader",
                          GIT_CONFIG_VALUE_0=f"AUTHORIZATION: basic {basic}")
    opts.adopt = dict(a.split("=", 1) for a in opts.adopt)
    mono = Mono(opts.ref, org, opts.monorepo)
    tips = DataTips(mono)
    remote = Remote(opts.remote_template, opts.owner)
    hub = GitHub(opts.github, opts.owner, opts.monorepo, opts.assume_locked, opts.assume_green, opts.wait_minutes)

    errors, synced = 0, []
    for t in targets:  # data repositories first
        summary(f"### {opts.owner}/{t.repo} <- {t.folder}/")
        try:
            synced.append((t, mirror_target(t, mono, tips, remote, hub, opts)))
        except MirrorError as e:
            summary(f"  ERROR: {e}")
            errors += 1
            if t.is_data:  # tool gitlinks would point at a stale data commit
                tips.set(t.folder, t.anchor_old, [])
    for t, result in synced:
        summary(f"### {opts.owner}/{t.repo}: merge")
        try:
            merge_target(t, mono, remote, hub, opts, *result)
        except MirrorError as e:
            summary(f"  ERROR: {e}")
            errors += 1
    summary(f"mirror: {errors} error(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
