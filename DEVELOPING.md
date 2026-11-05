# Developing in the Neurobagel monorepo

This guide covers what is shared across the tools in this repository. Each tool's own setup and test commands are in the "Working in the monorepo" section of its README under `packages/`.

## Layout

| Path | What |
|---|---|
| `packages/<tool>/` | One tool, with its full history: `api`, `federation-api`, `annotation-tool`, `bagel-cli`, `query-tool` |
| `deploy/` | Docker Compose recipes (formerly neurobagel/recipes) |
| `testdata/` | Example data and API responses for tests (formerly neurobagel/neurobagel_examples) |
| `.github/` | CI, release and publishing workflows for the whole repository |
| `migration/` | Records and scripts of the migration to the monorepo (temporary) |
| `tools/` | Repository tools: `mirror.py` (the mirror to the old repositories) |
| `DEVELOPING.md` | This guide |

Inside the packages, the old submodule folders are now symlinks to the shared folders, for example `packages/api/recipes -> ../../deploy`. On Windows, enable symlinks (`git config core.symlinks true`, Developer Mode) before cloning. bagel-cli's data folders (`bagel/communities`, `bagel/pipeline-catalog`, `tests/bids-examples`) are still git submodules.

Files inside `packages/*/.github/`, `packages/*/.pre-commit-config.yaml`, `packages/*/.gitmodules`, `packages/*/.autorc` and `packages/*/CITATION.cff` are not used in this repository: only the root `.github/` and `.pre-commit-config.yaml` are active here. They are not dead code, though: during the monorepo trial they are the old repositories' CI and setup (see "The old repositories").

## Setup

```bash
git clone --recurse-submodules https://github.com/neurobagel/neurobagel.git
cd neurobagel
uv tool install pre-commit   # or: pipx install pre-commit
pre-commit install           # installs the pre-commit and post-merge hooks
```

Requirements: [uv](https://docs.astral.sh/uv/) for the Python tools, Node.js 20 and npm for the frontends, Docker for the images and the api integration tests.

Python tools each have their own `uv.lock` and environment; frontends each have their own `package-lock.json` and `node_modules`. There is no root workspace yet. Run each tool's commands from its folder.

The frontend pre-commit hooks (typecheck, lint, format) use the tool's `node_modules`: run `npm ci` in `packages/annotation-tool` and `packages/query-tool` once. After a pull or merge that changes a frontend's `package.json`, the post-merge hook runs `npm ci` there for you.

## Running tests

All Python tests run on Python 3.12 and 3.13 in CI. Pin the version locally too, because uv otherwise picks whatever Python it finds:

```bash
cd packages/api
uv sync --python 3.12 --group dev
uv run --python 3.12 pytest
```

| Tool | CI test command (in `packages/<tool>`) |
|---|---|
| api | `uv run --python 3.12 pytest -m "not integration"` |
| federation-api | `uv run --python 3.12 pytest` |
| bagel-cli | `uv run --python 3.12 pytest -m "integration or not integration"` (needs the submodules) |
| annotation-tool | `npm run typecheck`, `npm run lint:check`, `npm run format:check`, `npm run test:unit`, `npx cypress run --component`, `npx cypress run --e2e` (against `npm run preview`) |
| query-tool | `npm run lint:check`, `npm run format:check`, `npx cypress run --component`, `npx cypress run --e2e` (against `npm run preview`, with a `.env`) |

api's `integration` tests need a running graph store and are skipped in CI during the migration; they will move to a single global integration test suite. To run them locally, see the api README (`docker compose up -d test_graph` in `packages/api`).

A tool's CI runs when files in that tool change, or when shared files change: `deploy/`, `testdata/`, `.gitmodules`, or the tool's workflow and the shared test workflow (`.github/workflows/test-python.yml`, `test-node.yml`). Link checks and the PR checks run on every PR. Spelling (codespell) is checked by the pre-commit hooks, which pre-commit.ci runs on every PR.

`migration/check-unchanged.sh` (temporary, removed with `migration/`) lists the package changes made by the migration itself, against `migration/allowed-changes.txt`. It is a migration check, run locally by `migration/verify.sh`, not in CI.

## Pull request titles

PRs are squash-merged by default, and the PR title becomes the commit message. release-please reads these messages to decide releases, so **the PR title must be a [conventional commit](https://www.conventionalcommits.org/)**:

```
<type>[(<scope>)][!]: <description>
```

- Releasing types: `feat` (minor release), `fix`, `perf`, `revert` (patch release). `!` marks a breaking change; while a tool is on 0.x, a breaking change bumps the minor version.
- Non-releasing types: `docs`, `style`, `refactor`, `test`, `build`, `ci`, `chore`.
- Optional scope: the tool folder name (`api`, `federation-api`, `annotation-tool`, `bagel-cli`, `query-tool`), or `deps`/`deps-dev` (Dependabot).

Which tool a commit releases is decided by **the files it changes**, not by its scope.

The `pr checks` workflow rejects titles that are not conventional commits (with [action-semantic-pull-request](https://github.com/amannn/action-semantic-pull-request)). Its `release-preview` job writes what release-please would propose for the PR's commits (versions and changelog entries per tool) to the job summary.

### PRs that change more than one tool

A squash merge would give every changed tool the same changelog entry and version bump. So a PR with releasable changes for more than one tool must:

1. contain **one conventional commit per tool**, each touching only that tool's folder,
2. have a **non-releasing title** (`chore:`, `ci:`, ...),
3. be merged with a **merge commit** (never squash, never rebase).

This is a convention, checked by the reviewer (the PR template has a checklist item; the release preview shows the per-tool entries a merge commit would give). If such a PR is squashed by mistake with a non-releasing title, nothing is released; release the tools with a follow-up commit per tool. Multi-tool PRs that release nothing (`chore`, `ci`, `docs`, `build`, `test` only) can be squashed.

release-please also reads an override block from a merged PR's description (the marker `BEGIN\_COMMIT\_OVERRIDE`, written here with escaped underscores). Never write the marker literally unless you mean to override the commit messages, and never in a multi-tool PR: the override applies to every tool the PR touches.

## Releases

Each tool has its own version, changelog (`packages/<tool>/CHANGELOG.md`), tags `<tool>-v<version>` and GitHub Releases.

1. On every push to `main`, release-please updates **one combined release PR** ("chore: release main") with the next version and changelog entry of every tool that has releasable commits since its last release.
2. Merging that PR (squash) updates `.release-please-manifest.json`, the changelogs and the frontends' `package.json`. The `release` workflow then runs release-please again, which creates one GitHub Release, and with it the tag `<tool>-v<version>`, per released tool.
3. In the same workflow run, release-please's outputs start publishing for each released tool:
   - api, federation-api, query-tool: Docker images `v<version>` and `latest` (`docker-build.yml`)
   - bagel-cli: PyPI, then the Docker image `v<version>` and `latest` (`bagel-cli-release.yml`)
   - annotation-tool, query-tool: the sites on Netlify (`sites.yml`; it can also be run by hand for a released version)

   If a publishing job fails, use "Re-run failed jobs" on that `release` run.
4. Every push to `main` also builds `nightly` images of the tools whose files changed (`docker-nightly.yml`).

Python versions come from the tags through hatch-vcs (`<tool>-v*` tags here, `v*` tags in the old repository; the same settings work in both), so CI checkouts that build a Python package need the full history (`fetch-depth: 0`). The frontends' versions live in `package.json` and are bumped by release-please.

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
- Release PR changelogs link to a compare view of the new tag, which only exists after the merge; the link check excludes these links.

## Dependency updates

One `.github/dependabot.yml` covers every tool, checked weekly. Its PRs have `build` titles, so they release nothing.

| Ecosystem | Folders | Updates |
|---|---|---|
| GitHub Actions | `/` | All |
| Git submodules | `/` (bagel-cli's data submodules) | All, grouped in one PR |
| npm | `packages/annotation-tool`, `packages/query-tool` | Minor and patch, grouped into production and development dependencies; majors ignored |
| uv | `packages/api`, `packages/federation-api`, `packages/bagel-cli` | Security updates only |
| Docker | the four Dockerfile folders | Base images, grouped; majors ignored, and minor updates of `python` (they change the runtime Python) |

## Required status checks

None for now. When they are added, use **one always-running aggregator job** as the only required check. Path-filtered workflows that are skipped never report a status, so requiring them directly would block every PR that does not touch that tool.

## The old repositories

The monorepo is on trial for a few months. During the trial the old repositories (neurobagel/api, federation-api, annotation-tool, bagel-cli, query-tool, recipes, neurobagel_examples) are read-only mirrors of their folders here, and their own CI keeps running. If the monorepo is given up, development moves back to them with nothing to replay.

### How the mirror works

`.github/workflows/mirror.yml` runs `tools/mirror.py` on every push to `main` and nightly. For each old repository it:

1. Adds one commit to the branch `monorepo-mirror` for each commit on `main` that changes the folder (`packages/<tool>/`, `deploy/` for recipes, `testdata/` for neurobagel_examples). The commit holds the folder exactly as it is here, with the original author, date and message. The only change: the shared-data symlinks (`recipes`, `neurobagel_examples`) become submodule pointers to the mirrored recipes and neurobagel_examples commits. A `Monorepo-Commit:` trailer records the source commit.
2. Opens or updates one pull request from `monorepo-mirror` to `main`. The old repository's CI runs on it.
3. Once that CI passes, fast-forwards the old `main` to the branch (GitHub then marks the PR merged; the next change opens a new one), and pushes the new tags: `api-v0.13.0` here becomes `v0.13.0` there. The old repositories get no GitHub Releases.
4. Reports the old CI result as a commit status `mirror/<repo>` on the commit here. When the old CI fails (or the mirror hits an error) the mirror run fails: the mirror badge in the README turns red, and if the repository secret `MIRROR_DISCORD_WEBHOOK` is set, a message with the run link goes to Discord.

Step 3 needs two things: the repository variable `MIRROR_MERGE` set to `true` (by hand, after the switchover; never in the rehearsal repository), and a locked old repository (a ruleset restricts updates of `main`; the bot app is the only exception). Without both, the mirror only keeps the branch and a draft PR up to date: before the switchover the old repositories are still in use, and the draft only shows that the old CI passes on the mirrored code.

The mirror stops with an error, and writes nothing, if an old `main` has a commit it did not make. Port that commit here (below), then run the workflow by hand with `adopt: <repo>=<sha>`. After rebuilding the repository the mirror is run by hand with `reset`. `dry_run` shows what would be mirrored.

### Rules for the trial

- **Keep every package self-contained.** Each one builds and tests from its own folder with its own lockfile and configs. No npm or uv workspace with a root lockfile, no imports across packages, no Docker builds from the repository root, no root config replacing a package config (adding root configs is fine).
- **`packages/<tool>/.github/`, `.gitmodules` and the package configs are live:** they are the old repository's CI and setup. A change to a package's build or CI also updates its package workflows in the same PR.
- **Packages reach `deploy/` and `testdata/` only through the existing symlinks.** The `mirror-check` PR check fails on other symlinks leaving a package.
- **No renaming of package folders or tag prefixes, and no rewriting of `main`.**
- **Red old CI is a must-fix** (red mirror badge, Discord message): fix it here; the mirror merges once it passes. It does not block merging here. Old CI can differ from the CI here (wider Python ranges, bagel-cli's `--upgrade`).

### Porting a change from an old repository

The old repositories take no changes of their own. To bring an open PR (or any commits) over, apply its commits to the package folder and open a PR here:

```bash
git -C ../api fetch origin pull/123/head:pr-123
git -C ../api format-patch --stdout origin/main..pr-123 | git am -3 --directory=packages/api
```

The other way (when switching back): `git format-patch --relative=packages/api ... | git am -3` in the old repository.

## Repository settings

Applied by a maintainer with `migration/settings.sh` (see the script for the full list):

- Merge commits and squash merges allowed, rebase merges off. Squash is the default, with the PR title as the commit message and an empty body (so conventional-commit lines from individual commits cannot trigger releases).
- Branch protection on `main`: a PR with one approving review; no required status checks.
- Labels used by release-please (`autorelease: pending`, `autorelease: tagged`), Dependabot and bots (`_bot`, `dependencies`), external PRs (`_community`) and the stale workflow (`_flag:stale`).
- Repository variables (table above).
- Dependabot security updates and CodeQL default setup on.

Done by hand: give the repository access to the org secrets and the Neurobagel bot app; install the pre-commit.ci app for the repository; create the Netlify sites and their site-ID secrets (`NETLIFY_ANNOTATE_SITE_ID`, `NETLIFY_QUERY_SITE_ID`) before switching `SITE_DEPLOY` on.
