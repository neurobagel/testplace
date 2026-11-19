# Regenerating the monorepo from scratch

Until the switchover, the monorepo is never edited by hand. It is generated from the upstream repositories and the files in this directory by one script, `migrate.sh`. Every fix goes into one of these files (a script, a record or a patch), and the monorepo is then rebuilt from scratch. Rebuilding against the same upstream state gives identical commit hashes.

The plan behind all of this is `PLAN.md` (in the monorepo) or `../Neurobagel monorepo migration plan.md` (in the working copy).

## Where to run it

Run the scripts from the **working copy of this directory**, `monorepo-migration/migration/`. `migrate.sh` reads the plan one level up. The copy of `migration/` inside neurobagel/neurobagel is a record of the build that produced it.

Never put scratch output (clones, builds, logs) inside `migration/`: `migrate.sh` copies this whole directory into the monorepo. Use `../work/` instead.

## Requirements

- git, [uv](https://docs.astral.sh/uv/) (PyYAML and git-filter-repo are pulled in through `uv run`), jq
- Docker, or Podman with a `docker` CLI. The checks build images and run the frontend tests in `docker.io/cypress/included`.
- `gh`, logged in. Only needed to regenerate `commit-rewrites.yaml`.
- `actionlint`, for the checks (pre-commit is run through `uvx pre-commit@4.7.0`)
- Network access to GitHub and Docker Hub

## Files

| File | What it is |
|---|---|
| `migrate.sh` | Builds the monorepo: import, migration/ commit, patches, checks. Never pushes. |
| `import.sh`, `import_helper.py` | The history import (git filter-repo per tool, merged into one history; shared data; symlinks; submodules) |
| `names.yaml` | **Input.** The single map of repositories, folders, tag prefixes and published artifact names |
| `commit-rewrites.yaml` | **Input.** Conventional-commit titles for upstream commits since each tool's last release (so release-please picks them up) |
| `gen-commit-rewrites.py` | Regenerates `commit-rewrites.yaml` from the PRs' release labels |
| `patches/*.patch` | **Input.** The monorepo setup, one concern per patch: root files, CI, release-please, publishing, README sections, the mirror |
| `import-sources.txt`, `tag-map.txt` | **Generated** by the import: the upstream commits imported, and old tag → new tag |
| `verify.sh`, `verify-setup.sh`, `verify-readme.sh`, `verify-mirror.sh` | The checks (H1-H10 history, S1-S11 setup) |
| `check-unchanged.sh`, `allowed-changes.txt` | Lists every package file the migration changed; fails on anything not on the allowlist |
| `baseline.md` | Upstream test counts the checks compare against (also `BASELINE_*` in `verify-setup.sh`) |
| `settings.sh`, `switchover.sh`, `old-repos-disabled.txt` | Repository settings, and locking the old repositories at switchover |
| `RUN_NOTES.md`, `inventory.md` | Record of every run, decision and finding |

## Quick start

```bash
cd monorepo-migration/migration
./migrate.sh ../work/build --work-dir="$PWD/../work/build-scratch"
```

This takes about 35 minutes with the full checks. It ends with `verify: all checks passed`, or a list of `FAIL` lines. The target must not exist, be empty, or be a git repository without commits, e.g. a fresh `git init` with a remote.

Options:
- `--no-verify`: build only, about 4 minutes.
- `--no-patches`: history import and migration/ commit only. Used to set up the patch repository; see "Changing a patch" below.
- `--work-dir=DIR`: scratch space for the import and the checks. The default is next to the target.

## What `migrate.sh` does

1. **`import.sh`.** For each package in `names.yaml` (the tools, into `tools/<tool>/`, and recipes, into `recipes/`):
   - fresh clone;
   - `git filter-repo` into its folder, with tags renamed to `<name>-vX.Y.Z`, `#N` references qualified to the original repository, and the titles from `commit-rewrites.yaml` applied;
   - merge into one history.

   Then:
   - neurobagel_examples is copied (as plain files, current main) to `examples/`;
   - the tools' recipes and neurobagel_examples submodules are replaced by relative symlinks to `recipes/` and `examples/`; the monorepo has no submodules;
   - `import-sources.txt` and `tag-map.txt` are written.

   All commits get a fixed identity and the date of the newest upstream commit. That's why the migration's commits look a few days old: the fixed date makes builds reproducible.
2. **Commits this directory** as `migration/` (the plan becomes `migration/PLAN.md`).
3. **Applies `patches/*.patch`** with `git am`. It fills in two values derived from the import, so these never need editing in the patches:
   - release-please's `bootstrap-sha`: the last import commit;
   - each tool's version in `.release-please-manifest.json`: its latest release tag **on main**. Upstream tags on no branch are ignored.
4. **Runs `verify.sh`.**

## Before a rebuild against newer upstream (refresh)

1. **See what changed upstream** since the last import. The imported commits are in `import-sources.txt`. If nothing changed, skip to step 5.
2. **Commit titles.** Run, with a scratch directory **outside** `migration/`:
   ```bash
   uv run --no-project --quiet --with pyyaml==6.0.3 python gen-commit-rewrites.py ../work/rewrites
   ```
   It adds entries for new non-conventional titles, derived from the PRs' release labels. Existing entries are kept. Entries it can't derive get `new: null`; the maintainer resolves those, because `import.sh` refuses to run while any are left. (`IMPORT_ALLOW_UNRESOLVED=1` allows development runs.)
3. **Test baseline.** If upstream changed tests, re-measure the counts on upstream (same commands and Python versions as in `baseline.md`). Then update `baseline.md` and `BASELINE_*` in `verify-setup.sh`.
4. **Old repositories' workflows.** Diff each old repository's `.github/` since the inventory, to catch new workflows to port, or to disable at switchover (`old-repos-disabled.txt`).
5. **Run `migrate.sh`.** If `git am` fails, upstream changed a file a patch touches: update the patch (below) and run again.

## Changing a patch

Patches are authored as commits in a patch repository, then exported.

```bash
# Set up the patch repository: the import plus the migration/ commit, then the patches as commits
./migrate.sh ../work/dev --no-patches --no-verify
base=$(git -C ../work/dev rev-parse HEAD)   # the migration/ commit; the patches go on top
git -C ../work/dev am --committer-date-is-author-date "$PWD"/patches/*.patch
```

To change a patch, fix the files in `../work/dev` and commit the change as a fixup of that patch's commit. Use the fixed date, so the exported patches stay byte-identical when nothing else changes:

```bash
cd ../work/dev
d=$(git log -1 --format=%ct HEAD)
GIT_AUTHOR_DATE="@$d +0000" GIT_COMMITTER_DATE="@$d +0000" git commit -q --fixup=<patch commit>
GIT_SEQUENCE_EDITOR=: git rebase -q -i --autosquash --committer-date-is-author-date "$base"
```

Then re-export the whole series:

```bash
rm ../../migration/patches/*.patch
git format-patch -q --zero-commit -o ../../migration/patches "$base"
```

A new concern gets a new commit, and with it a new patch file. Keep one concern per patch, and keep package edits minimal: every file a patch changes under `tools/` or `recipes/` must be listed in `allowed-changes.txt`, and must work unchanged in the old repository too, because the mirror copies the folder as it is.

## Checking a build

```bash
./verify.sh <monorepo-dir> <scratch-dir>
```

| Check | What it covers |
|---|---|
| H1-H10 | History: commit and tag counts, every tag's tree, PR references, title rewrites, package trees vs upstream, examples/, symlinks and their upstream pins, no submodules, root layout |
| S1 | check-unchanged |
| S2 | release configuration (incl. which commit types release), publishing and nightly jobs, per-tool Python versions, actionlint |
| S3, S4 | Environments (every tool on each of its Python versions); the commit hooks (root pre-commit config, running every tool's own config) |
| S5, S6 | pytest counts per tool and Python version; versions from tags |
| S7 | configure-nb wheel and sdist contents |
| S8 | Images built and their file listings compared with upstream's |
| S9 | Every guard fires on a deliberate failure |
| S10 | README commands run word for word, including query-tool's full Cypress suites and a recipes deployment |
| S11 | Mirror round trip into local copies of the old repositories |

Checks marked `CI` can only be checked on GitHub; they are listed for the rehearsal.

`VERIFY_SKIP=tests,images,readme,mirror` skips slow parts for development runs. Skipped checks count as failures, so a gate run uses no skips. S10 is about half the run time, and it is the only local run of query-tool's tests.

To avoid repeating a full run: if a new build has the same inputs as one that passed, compare the trees instead. The root tree without `migration/` should be identical:

```bash
git -C <build> ls-tree HEAD | grep -v $'\tmigration$' | git hash-object --stdin
```

## Pushing a build

Claude Code builds and commits, but never pushes; the maintainer pushes.

- **Rehearsal (neurobagel/testplace).** Build anywhere, then move the local `testplace` clone onto the build. The maintainer force-pushes it. The mirror then rebuilds its branches in the old repositories by itself.
  ```bash
  cd testplace
  git fetch <build> +main:refs/remotes/rebuild/main '+refs/tags/*:refs/tags/*'
  git reset --hard rebuild/main
  git update-ref -d refs/remotes/rebuild/main
  git push --force origin main
  git push --force origin --tags
  ```
- **Switchover (neurobagel/neurobagel).** Lock the old repositories first (`switchover.sh`), then refresh and build from that locked state into the empty `neurobagel/` clone with the full checks, and push main and all tags. The full sequence is in the plan, Phase 5.

## Things that have bitten us

- **Upstream moves during the import.** A tag can appear while the import runs, possibly pointing at a commit that isn't on main. Versions only count tags on main. If a build looks inconsistent, rebuild.
- **`gen-commit-rewrites.py` clones into the directory you give it.** Never pass a path inside `migration/`.
- **Package changes must work in the old repository too.** One example: a README link to `../../DEVELOPING.md` works in the monorepo but is broken in the old repository. Use absolute URLs; the mirror's PR check (`tools/mirror.py --check`) catches this.
