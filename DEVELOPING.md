# Developing in the Neurobagel monorepo

This guide covers what is shared across the folders in this repository. Each tool's own setup and test commands are in the "Working in the monorepo" section of its README.

## Layout

| Path | What |
|---|---|
| `tools/<tool>/` | One tool, with its full history: `api`, `federation-api`, `query-tool`, `configure-nb` |
| `recipes/` | Docker Compose recipes for deploying Neurobagel, with their full history (formerly neurobagel/recipes) |
| `examples/` | Example data and API responses for tests (formerly neurobagel/neurobagel_examples) |
| `shared/` | Configs shared by several tools, copied into the tool folders (see "Shared configs") |
| `scripts/` | Repository scripts: `sync-shared.py` (shared configs), `mirror.py` (the mirror to the old repositories) |
| `.github/` | CI, release and publishing workflows for the whole repository |
| `migration/` | Records and scripts of the migration to the monorepo (temporary) |
| `DEVELOPING.md` | This guide |

Inside the tools, the old submodule folders are now symlinks: `tools/api/recipes -> ../../recipes` and `tools/api/neurobagel_examples -> ../../examples` (the same in `tools/query-tool`). On Windows, enable symlinks (`git config core.symlinks true`, Developer Mode) before cloning.

Each tool folder is self-contained: its configs (`pyproject.toml`, `.flake8`, `.codespellrc`, prettier, eslint, ...), its `.pre-commit-config.yaml` and its `.github/` folder stay inside it. The tool's `.github/` and `.gitmodules` are not used in this repository, but they are not dead code: during the monorepo trial they are the old repositories' CI and setup.

## Setup

```bash
git clone https://github.com/neurobagel/neurobagel.git
cd neurobagel
uv tool install prek   # or: pipx install prek
prek install           # installs the pre-commit and post-merge hooks
```

Requirements: [uv](https://docs.astral.sh/uv/) for the Python tools, Node.js 20 and npm for query-tool and recipes' end-to-end tests, Docker for the images, the recipes tests and the api integration tests.

Each Python tool has its own `uv.lock` and environment; query-tool has its own `package-lock.json` and `node_modules`. There is no root workspace. Run each tool's commands from its folder.

### Commit hooks

[prek](https://github.com/j178/prek) is a drop-in replacement for pre-commit that understands a repository with several `.pre-commit-config.yaml` files. `prek install` at the root sets up all of them: on each commit, prek runs every tool's own config (`tools/<tool>/.pre-commit-config.yaml`) from inside that tool's folder, on the files changed there, and the root `.pre-commit-config.yaml` (workflows, Dependabot config, shared configs) on the rest. The tool configs are the same files the old repositories use (with pre-commit or pre-commit.ci), so they keep working there.

- `prek run --all-files` checks everything; `prek run --all-files tools/api` only the api.
- query-tool's hooks (typecheck, lint, format) use its `node_modules`: run `npm ci` in `tools/query-tool` once. After a pull or merge that changes its `package.json`, the post-merge hook runs `npm ci` there for you.
- In CI the hooks run in the `prek` job of the `pr checks` workflow, on all files.

## Running tests

| Tool | CI test command (in the tool's folder) |
|---|---|
| api | `uv run --python <version> pytest -m "not integration"` |
| federation-api | `uv run --python <version> pytest` |
| configure-nb | `uv run --python <version> pytest` |
| query-tool | `npm run lint:check`, `npm run format:check`, `npx cypress run --component`, `npx cypress run --e2e` (against `npm run preview`, with a `.env`) |
| recipes | two local nodes and a portal from the released images, then Cypress end-to-end tests (`.github/workflows/recipes.yml`) |

**Python versions are set per tool**, in the tool's own test workflow: the `python-version` list of `tools/<tool>/.github/workflows/test.yaml`. That file runs the old repository's CI, and the monorepo CI reads the same list, so one edit changes both. Pin the version locally too, because uv otherwise picks whatever Python it finds:

```bash
cd tools/api
uv sync --python 3.12 --group dev
uv run --python 3.12 pytest
```

api's `integration` tests need a running graph store and are skipped in CI during the migration; they will move to a single global integration test suite. To run them locally, see the api README.

A tool's CI runs when files in that tool change, or when what it uses changes: `recipes/` and `examples/` for api and query-tool, the tool's workflow, and the shared test workflow (`.github/workflows/test-python.yml`, `test-node.yml`). Link checks and the PR checks run on every PR.

recipes has a scheduled compatibility test (twice a day): it deploys the `latest` and the `nightly` images and runs the end-to-end tests, and posts to Slack when it fails (secret `NB_SLACK_WEBHOOK`).

`migration/check-unchanged.sh` (temporary, removed with `migration/`) lists the changes the migration itself made inside the imported folders, against `migration/allowed-changes.txt`. It is a migration check, run locally by `migration/verify.sh`, not in CI.

## Shared configs

A config used by one tool lives in that tool's folder, and only there. Change it together with the code it affects, in the same PR.

A config shared by several tools lives once in `shared/`, and `shared/files.yaml` lists which tool folders get a copy of it:

```yaml
- source: shared/codespell-ignore.txt
  copies:
    - tools/api/codespell-ignore.txt
    - tools/federation-api/codespell-ignore.txt
```

`scripts/sync-shared.py` writes the copies. It runs as a commit hook (it updates the copies; commit them) and in the `prek` CI job (fails if a copy differs). The copies are ordinary files in the tool folders, so each tool stays self-contained and its old repository gets them too. Never point a tool config at a file outside its folder: the old repository has no such file.

## Pull request titles

PRs are squash-merged by default, and the PR title becomes the commit message. release-please reads these messages to decide releases, so **the PR title must be a [conventional commit](https://www.conventionalcommits.org/)**:

```
<type>[(<scope>)][!]: <description>
```

The type decides the release and the changelog section:

| Type | Release | Changelog section |
|---|---|---|
| `feat` | minor | 🚀 Enhancements |
| `fix` | patch | 🐛 Bug Fixes |
| `perf` | patch | 🏎 Performance Improvements |
| `refactor`, `revert` | patch | 🏠 Internal |
| `docs`, `test`, `chore`, `ci`, `build`, `style` | none | not listed |

`!` marks a breaking change ("⚠ BREAKING CHANGES" in the changelog); while a tool is on 0.x, a breaking change bumps the minor version. Use `refactor` for an internal change that should be released (the old `pr-internal` label), and `chore` for one that should not (`skip-release`).

Optional scope: `api`, `federation-api`, `query-tool`, `configure-nb`, `recipes`, `examples`, or `deps` (Dependabot). Which tool a commit releases is decided by **the files it changes**, not by its scope.

The `pr checks` workflow rejects titles that are not conventional commits (with [action-semantic-pull-request](https://github.com/amannn/action-semantic-pull-request)). Its `release-preview` job writes what release-please would propose for the PR's commits (versions and changelog entries per tool) to the job summary.

### PRs that change more than one tool

A squash merge would give every changed tool the same changelog entry and version bump. So a PR with releasable changes for more than one tool must:

1. contain **one conventional commit per tool**, each touching only that tool's folder,
2. have a **non-releasing title** (`chore:`, `ci:`, ...),
3. be merged with a **merge commit** (never squash, never rebase).

This is a convention, checked by the reviewer (the PR template has a checklist item; the release preview shows the per-tool entries a merge commit would give). If such a PR is squashed by mistake with a non-releasing title, nothing is released; release the tools with a follow-up commit per tool. Multi-tool PRs that release nothing (`chore`, `ci`, `docs`, `build`, `test` only) can be squashed.

release-please also reads an override block from a merged PR's description (the marker `BEGIN\_COMMIT\_OVERRIDE`, written here with escaped underscores). Never write the marker literally unless you mean to override the commit messages, and never in a multi-tool PR: the override applies to every tool the PR touches.

## Releases

Each tool and recipes has its own version, changelog (`<folder>/CHANGELOG.md`), tags `<name>-v<version>` and GitHub Releases.

1. On every push to `main`, release-please updates **one combined release PR** ("chore: release main") with the next version and changelog entry of every tool that has releasable commits since its last release.
2. Merging that PR (squash) updates `.release-please-manifest.json`, the changelogs and query-tool's `package.json`. The `release` workflow then runs release-please again, which creates one GitHub Release, and with it the tag `<name>-v<version>`, per released tool, and adds an "Authors" list (the authors of the released PRs) to each GitHub Release.
3. In the same workflow run, release-please's outputs start publishing for each released tool:
   - api, federation-api, query-tool: Docker images `v<version>` and `latest` (`docker-build.yml`)
   - configure-nb: PyPI (`configure-nb-release.yml`)
   - query-tool: the site on Netlify (`sites.yml`; it can also be run by hand for a released version)
   - recipes: nothing beyond the GitHub Release

   If a publishing job fails, use "Re-run failed jobs" on that `release` run.
4. Every push to `main` that changes an image tool also builds its `nightly` image, after its tests pass (the `nightly` job in the tool's workflow).

The changelogs keep the sections of the earlier auto changelogs. Unlike auto, release-please does not list `docs` and `test` changes (they never trigger a release, so they are hidden), and it does not comment "released in" on PRs.

Python versions come from the tags through hatch-vcs (`<tool>-v*` tags here, `v*` tags in the old repository; the same settings work in both), so CI checkouts that build a Python package need the full history (`fetch-depth: 0`). query-tool's version lives in `package.json` and is bumped by release-please.

Publishing targets come from repository variables, so the same workflows publish to test targets during validation:

| Variable | Validation | Production |
|---|---|---|
| `IMAGE_REGISTRY` | `ghcr.io` | `docker.io` |
| `IMAGE_NAMESPACE` | `neurobagel` | `neurobagel` |
| `PYPI_REPOSITORY_URL` | `https://test.pypi.org/legacy/` (with a TestPyPI `PYPI_TOKEN` repository secret) | unset (PyPI) |
| `SITE_DEPLOY` | `false` | `true` |
| `MIRROR_OWNER` | `neurobagel` (draft mirror PRs only, until the old repositories are locked) | `neurobagel` |
| `MIRROR_MERGE` | unset (the mirror never merges or tags) | `true`, set by hand after the switchover |

`images-validation.yml` (manual, temporary: for the migration's validation phase) builds and pushes every image with a `validation-<sha>` tag.

Good to know:

- The release PR is only updated when new releasable commits land on `main`. A `ci:` or `chore:` fix does not touch it, so its CI does not rerun.
- "Re-run jobs" on a PR reuses the old test merge with the old base. To test against the current `main`, close and reopen the PR, or push to it.
- Release PR changelogs link to a compare view of the new tag, which only exists after the merge; link checks ignore these links.

## Dependency updates

One `.github/dependabot.yml` covers every folder, checked weekly. Its PRs have `build` titles, so they release nothing.

| Ecosystem | Folders | Updates |
|---|---|---|
| GitHub Actions | `/` | All |
| npm | `tools/query-tool`, `recipes` | Minor and patch, grouped into production and development dependencies; majors ignored |
| uv | `tools/api`, `tools/federation-api`, `tools/configure-nb` | Security updates only |
| Docker | `tools/api`, `tools/federation-api`, `tools/query-tool` | Base images, grouped; majors ignored, and minor updates of `python` (they change the runtime Python) |

## Required status checks

None for now. When they are added, use **one always-running aggregator job** as the only required check. Path-filtered workflows that are skipped never report a status, so requiring them directly would block every PR that does not touch that tool.

## The old repositories

The monorepo is on trial for a few months. During the trial the old repositories (neurobagel/api, federation-api, query-tool, configure-nb, recipes, neurobagel_examples) are read-only mirrors of their folders here, and their own CI keeps running. If the monorepo is given up, development moves back to them with nothing to replay. (neurobagel/annotation-tool and neurobagel/bagel-cli are not part of the monorepo yet and are developed as before.)

### How the mirror works

`.github/workflows/mirror.yml` runs `scripts/mirror.py` on every push to `main` and nightly. For each old repository it:

1. Adds one commit to the branch `monorepo-mirror` for each commit on `main` that changes the folder (`tools/<tool>/`, `recipes/`, `examples/` for neurobagel_examples). The commit holds the folder exactly as it is here, with the original author, date and message. The only change: the symlinks `recipes` and `neurobagel_examples` in api and query-tool become submodule pointers to the mirrored recipes and neurobagel_examples commits. A `Monorepo-Commit:` trailer records the source commit.
2. Opens or updates one pull request from `monorepo-mirror` to `main`. The old repository's CI runs on it.
3. Once that CI passes, fast-forwards the old `main` to the branch (GitHub then marks the PR merged; the next change opens a new one), and pushes the new tags: `api-v0.13.0` here becomes `v0.13.0` there. The old repositories get no GitHub Releases.
4. Reports the old CI result as a commit status `mirror/<repo>` on the commit here. When the old CI fails (or the mirror hits an error) the mirror run fails, and the mirror badge in the README turns red.

Step 3 needs two things: the repository variable `MIRROR_MERGE` set to `true` (by hand, after the switchover; never in the rehearsal repository), and a locked old repository (a ruleset restricts updates of `main`; the bot app is the only exception). Without both, the mirror only keeps the branch and a draft PR up to date: before the switchover the old repositories are still in use, and the draft only shows that the old CI passes on the mirrored code.

The mirror stops with an error, and writes nothing, if an old `main` has a commit it did not make. Port that commit here (below), then run the workflow by hand with `adopt: <repo>=<sha>`. After rebuilding the repository the mirror is run by hand with `reset`. `dry_run` shows what would be mirrored.

### Rules for the trial

- **Keep every tool self-contained.** Each one builds and tests from its own folder with its own lockfile and configs. No npm or uv workspace with a root lockfile, no imports across tools, no Docker builds from the repository root, no tool config that refers to a file outside its folder (shared configs are copied in, see "Shared configs").
- **`tools/<tool>/.github/`, `.gitmodules`, `.pre-commit-config.yaml` and the tool configs are live:** they are the old repository's CI and setup. A change to a tool's build or CI also updates its own workflows in the same PR. The Python versions in `tools/<tool>/.github/workflows/test.yaml` are the ones both CIs test.
- **Tools reach `recipes/` and `examples/` only through the existing symlinks.** The `mirror-check` PR check fails on other symlinks leaving a folder, and on relative Markdown links leaving a folder (use absolute URLs; they would break in the old repository).
- **No renaming of folders or tag prefixes, and no rewriting of `main`.**
- **Red old CI is a must-fix** (red mirror badge): fix it here; the mirror merges once it passes. It does not block merging here. Old CI can differ from the CI here (configure-nb's old CI installs with `--upgrade`).

### Porting a change from an old repository

The old repositories take no changes of their own. To bring an open PR (or any commits) over, apply its commits to the folder and open a PR here:

```bash
git -C ../api fetch origin pull/123/head:pr-123
git -C ../api format-patch --stdout origin/main..pr-123 | git am -3 --directory=tools/api
```

For recipes use `--directory=recipes`. The other way (when switching back): `git format-patch --relative=tools/api ... | git am -3` in the old repository.

## Repository settings

Applied by a maintainer with `migration/settings.sh` (see the script for the full list):

- Merge commits and squash merges allowed, rebase merges off. Squash is the default, with the PR title as the commit message and an empty body (so conventional-commit lines from individual commits cannot trigger releases).
- Branch protection on `main`: a PR with one approving review; no required status checks.
- Labels used by release-please (`autorelease: pending`, `autorelease: tagged`), Dependabot and bots (`_bot`, `dependencies`), external PRs (`_community`) and the stale workflow (`_flag:stale`).
- Repository variables (table above).
- Dependabot security updates and CodeQL default setup on.

Done by hand: give the repository access to the org secrets and the Neurobagel bot app; create the Netlify site and its site-ID secret (`NETLIFY_QUERY_SITE_ID`) before switching `SITE_DEPLOY` on; a PyPI token for configure-nb (`PYPI_TOKEN`).
