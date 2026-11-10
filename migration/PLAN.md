# Neurobagel monorepo migration plan

How to use this plan (for Claude Code): Scope, Decisions and Requirements describe the target state. Migration steps describe the order of work, in phases that each end with a gate where you stop and wait for the maintainer. Follow the working rules in Migration steps at all times. Open questions are resolved with the maintainer at the gate where they first matter.

## Scope

Move the five core Neurobagel tools, plus recipes and neurobagel\_examples, into one monorepo with full history, without changing any published artifact. The monorepo starts as a trial of about 3-4 months: during the trial the old repos are read-only mirrors of the monorepo, with their CI running, so switching back stays safe and easy (see Mirror to the old repos). *(Revised 2026-11-09, mirror decision.)*

In scope (with history):

- api (n-API): https://github.com/neurobagel/api
- federation-api (f-API): https://github.com/neurobagel/federation-api
- annotation-tool: https://github.com/neurobagel/annotation-tool
- bagel-cli: https://github.com/neurobagel/bagel-cli
- query-tool: https://github.com/neurobagel/query-tool

In scope (copied in as plain files, replacing submodules):

- recipes: https://github.com/neurobagel/recipes (used by api, query-tool)
- neurobagel\_examples: https://github.com/neurobagel/neurobagel\_examples (used by api, query-tool, bagel-cli)

Kept as git submodules at their current paths inside bagel-cli (declared in the root .gitmodules):

- communities: https://github.com/neurobagel/communities (bagel/communities, packaged into the bagel wheel)
- pipeline-catalog: https://github.com/nipoppy/pipeline-catalog (bagel/pipeline-catalog, packaged into the bagel wheel)
- bids-examples: https://github.com/bids-standard/bids-examples (tests/bids-examples, tests only)

Out of scope for now: documentation (will move in later), communities, menu, workflows, planning.

## Decisions

Decided:

- Monorepo name: neurobagel/neurobagel (may change later, see Renaming later).
- Names are provisional and may change later (see Renaming later). Starting names: packages/\<name> with \<name> one of api, federation-api, annotation-tool, bagel-cli, query-tool; the same \<name> as tag prefix and release-please component. Directory name and tag prefix are configured separately so either can change without the other.
- Tag format: \<component>-v\<version>. Existing tags are prefixed, e.g. v0.10.0 becomes api-v0.10.0.
- Python versions keep coming from git tags via hatch-vcs, with settings that work unchanged in the monorepo and in the old repo: search\_parent\_directories = true (instead of root = "../.."), tag\_regex with an optional \<tool>- prefix, git\_describe\_command matching \<tool>-v\* and v\*. CI checkouts use fetch-depth: 0. *(Revised 2026-11-09, mirror decision.)* (Tested in scratch repos: correct versions in both layouts, other tools' tags ignored.) JS versions stay in package.json, bumped by release-please.
- Submodules: shared data used by several tools is copied in; bagel-cli's own data submodules stay submodules. recipes (HEAD of main) is copied to deploy/ and neurobagel\_examples to testdata/; these are the only copies and packages reach them through symlinks. communities, pipeline-catalog and bids-examples stay submodules at their current paths and pins inside bagel-cli, declared in the root .gitmodules, so the wheel, sdist and nightly image build as upstream. These are the only submodules in the monorepo.
- Published artifact names do not change: PyPI bagel, Docker Hub neurobagel/api, neurobagel/federation\_api, neurobagel/query\_tool, static site deploys.
- Image registries: Docker Hub for production; ghcr for validation before going live (Phase 4 rehearsal). Registry and namespace come from repository variables. Images are for production only during migration (no dev environments or test stacks built from them). Each image builds from its own package folder with its existing Dockerfile, as upstream. Exception: bagel-cli's nightly image needs the version from the monorepo's git tags, so it gets one small change (root-context build or version passed as a build argument).
- Old repos: read-only mirrors during the trial. Until switchover they stay fully live and the team keeps working there. At switchover they are locked by a ruleset (the bot app is the only bypass), their release and publishing workflows are disabled, and from then on they receive every monorepo change through mirror PRs. Their main, tags and CI stay usable, so switching back means stopping the mirror and unlocking them. *(Revised 2026-11-09, mirror decision.)*
- Rehearsal and switchover are separate. Before switchover the monorepo lives in a scratch repository (neurobagel/testplace), rebuilt from scratch and pushed as often as wanted. The first push to neurobagel/neurobagel is the switchover push, made from the locked state of the old repos. Nothing from the rehearsal is carried over by hand; whatever is worth keeping goes into the pipeline (patch, script, settings.sh). *(Revised 2026-11-09, mirror decision.)*
- All tools switch over at once. A staged switchover (one tool imported later) is a documented fallback only, see Staged switchover (fallback). *(Revised 2026-11-09, mirror decision.)*
- Publishing: only the monorepo publishes, from switchover on. Old repos get tags (vX.Y.Z), no GitHub Releases. *(Revised 2026-11-09, mirror decision.)*
- Issues are outside the migration: they stay in the old repos or are transferred separately (e.g. in the GitHub web interface). *(Revised 2026-11-09, mirror decision.)*
- Releases: release-please, one combined release PR for all tools ("separate-pull-requests": false, set explicitly; the default is one PR per tool), independent per-tool versions, tags, changelogs and GitHub Releases. Breaking changes bump the minor version while tools stay on 0.x ("bump-minor-pre-major": true). *(Added 2026-11-09, Gate 2.)* *(Revised 2026-11-09, Gate 3 review: GitHub Releases on, so release-please creates the tags itself; see Tags.)*
- Merge policy: squash is the default, with the PR title as the commit message; PR titles must be conventional commits. A PR with releasable changes for more than one tool contains one conventional commit per tool (each touching only that tool), has a non-releasing title (chore:, ci:, ...) and is merged with a merge commit, never squashed or rebased. Multi-tool PRs that release nothing can be squashed. The merge method is a convention checked at review (PR template checklist, release preview), not by a CI check. *(Revised 2026-11-09, Gate 3 review.)*
- Upstream commits since each tool's last release whose titles are not conventional commits (e.g. \[FIX\], \[ENH\]) are rewritten to conventional commits during import, so release-please picks them up. The type is derived from the PR's release label; if unclear, ask a maintainer. Every rewrite is documented in migration/. Label mapping (Gate 2): pr-major-breaking and pr-minor-breaking -> feat!, pr-minor -> feat, pr-patch and pr-bug-fix -> fix, pr-performance -> perf, pr-documentation -> docs, pr-tests -> test, pr-dependencies and dependencies -> build(deps), pr-internal, skip-release and \_bot -> chore. All GitHub autolink references #N in commit messages are qualified, not only (#N). *(Added 2026-11-09, Gate 2.)*
- Per-tool CITATION.cff files stay as dead code; their validation is not ported. A single root citation file may come later.
- No required status checks for now.
- No npm workspace during migration: annotation-tool and query-tool stay independent npm projects with their own package-lock.json. The npm workspace is introduced after migration, as part of aligning React (and MUI) major versions across both frontends.
- Python test matrix: the intersection of the current supported ranges of api, federation-api and bagel-cli (expected around 3.11-3.13; confirm from each pyproject.toml). Every test command pins its Python version explicitly. bagel-cli is known to fail at import on 3.11 with its locked dependencies (upstream hides this with --upgrade); confirm whether 3.11 stays in the matrix. *(Revised 2026-11-09, Phase 3: with per-package locks, bagel-cli fails at import on 3.11, so the shared matrix is 3.12-3.13, locked dependencies, no --upgrade.)*
- Tests that need a real running service (e.g. api tests against a graph store) are skipped in CI during migration and return as part of a single global integration test suite. Tests that mock other tools stay and keep running as they do today; they mark what needs moving into the global suite later.
- Minimal change: package code stays as identical to the original repos as possible; every edit inside packages/ must be required by the migration, and is enforced by a check (see Requirements).
- Bot token: org-level bot app (NB\_BOT\_ID, NB\_BOT\_KEY), used by release-please so release PRs trigger CI.
- Python dependencies: no uv workspace during migration. Each Python package keeps its own uv.lock and venv (as the frontends keep their own package-lock.json), because the api and federation-api images build from the package uv.lock on Python 3.10 and api and federation-api both ship a top-level `app` package. The uv workspace comes later, together with images built from a root lock. *(Revised 2026-11-09, Phase 3.)*
- Tags: release-please creates a GitHub Release per released tool, and with it the \<component>-v\<version> tag (it creates tags only together with GitHub Releases; with skip-github-release it creates none). Publishing runs from release-please's per-package outputs (release\_created, version) in the release workflow, as in the neurobagel/develop test run; no tag parsing and no custom tagging script. *(Revised 2026-11-09, Gate 3 review.)* *(Phase 3 had used skip-github-release plus an own tagging job, tag-release.sh; dropped because the version chain then depended on a second piece of code.)*
- No custom workflow scripts (.github/scripts): prefer existing actions (action-semantic-pull-request, dorny/paths-filter, docker/metadata-action) and short inline steps. *(Revised 2026-11-09, Gate 3 review.)* One exception: the mirror script tools/mirror.py; no existing tool copies a folder with its history onto an existing repo and swaps symlinks for gitlinks (git subtree split cannot fast-forward the old main, Copybara has no gitlink support, josh needs a proxy server). *(Revised 2026-11-09, mirror decision.)*

Open:

- bagel-cli nightly image: root-context build or version as build argument (decide in Phase 3, whichever is the smaller change). *(Resolved 2026-11-09: version as build argument, one `ARG SETUPTOOLS_SCM_PRETEND_VERSION` line in Dockerfile.nightly.)*
- *(Resolved 2026-11-09: tags via own tagging job; Python matrix 3.12-3.13.)* *(Revised at the Gate 3 review: tags via GitHub Releases created by release-please.)*

## Requirements

History and layout:

- Each tool in packages/\<name>/ with its full history, file paths rewritten so per-package git log works.
- Commit messages rewritten so PR references point to the original repo: (#123) becomes (neurobagel/api#123).
- Tags prefixed with the tool name (see Decisions). All tags are pushed explicitly at one point, before anything that needs versions. Three query-tool tags point at a commit on no branch; keep them as upstream does.
- Non-conventional upstream commit titles since each tool's last release rewritten to conventional commits (see Decisions), from a committed mapping file so replays are deterministic.
- Package contents stay as close to the original repo as possible. Package .github/, .gitmodules and configs are live, not dead code: during the trial they are the old repos' CI and setup. CITATION.cff stays as is. Required edits are limited to: hatch-vcs settings for prefixed tags, submodule gitlinks replaced by symlinks, and anything needed for tests and builds to run from the monorepo. Every edit must also work unchanged in the old repo, because the mirror copies the package folder as it is. *(Revised 2026-11-09, mirror decision.)*
- Submodules handled as in Decisions: recipes in deploy/ and neurobagel\_examples in testdata/, reached through relative symlinks so every package uses the same single copy; communities, pipeline-catalog and bids-examples as submodules at their existing paths inside bagel-cli, declared in the root .gitmodules. Gitlinks being replaced are removed before any submodule init; package .gitmodules files stay unchanged (unused in the monorepo, live in the old repos through the mirror).
- A temporary migration/ directory at the root with this plan (without the agent environment section), the import script and the commit rewrite log (developer docs are in the root DEVELOPING.md; revised 2026-11-09, Gate 3 review).

Root:

- MIT LICENSE (copied from bagel-cli) and a root README.
- uv workspace (Python). No npm workspace yet; each frontend keeps its own package-lock.json. *(Revised 2026-11-09, Phase 3: no uv workspace either; each Python package keeps its uv.lock, see Decisions.)*
- pre-commit hooks that run each package's existing linter and formatter configs. Each hook is scoped to its package folder and passes its config path explicitly. isort gets --settings-path only, never --src. The docker-compose hook matches compose files only. Upstream's post-merge npm ci hook becomes a pre-commit post-merge hook (default\_install\_hook\_types: \[pre-commit, post-merge\], default\_stages: \[pre-commit\]). No repo-wide reformat during migration.
- PR title check for conventional commits (types, optional tool scope) with amannn/action-semantic-pull-request, plus an informational release preview (release-please dry run in the PR's job summary). The multi-tool merge policy is a review convention, not a CI check. *(Revised 2026-11-09, Gate 3 review.)*
- check-unchanged.sh: compares every file under packages/ with upstream and fails unless the change is on an allowlist of migration-required edits. Runs locally in verify.sh only, not in CI: after switchover every PR changes packages/, and the mirror check takes over. *(Revised 2026-11-09, mirror decision.)*
- One root dependabot.yml with directories and groups, validated by a check-dependabot hook, including a gitsubmodule entry for the three bagel-cli submodules. Python version updates off (security only, as upstream); Docker on with majors ignored, and with minor updates of the python base image ignored (python:3.10 -> 3.13 counts as minor but changes the runtime Python); Docker base image updates and submodule updates grouped into one PR each; every entry uses commit-message prefix "build" so its PRs pass the title check and release nothing. *(Revised 2026-11-09, Gate 3 review, from the neurobagel/develop test run.)*
- A root DEVELOPING.md (not in migration/, which is removed later) and a short "Working in this repository" section in the root README pointing to it. *(Revised 2026-11-09, Gate 3 review.)*
- Spelling: codespell for all five packages runs as pre-commit hooks (pre-commit.ci), with each package's .codespellrc; the frontends ran it in CI upstream. *(Revised 2026-11-09, Gate 3 review.)*
- Each tool's README gets a monorepo section, written once at the end of Phase 3 and checked by running its commands word for word in a fresh clone. It opens with a sentence that reads correctly in both repos ("Development happens in neurobagel/neurobagel, in packages/\<dir>; neurobagel/\<repo> is a read-only mirror."), and replaces the separate README pointer in the old repos. *(Revised 2026-11-09, mirror decision.)*

CI (root .github/ only):

- Path-filtered per-package tests via reusable workflows (e.g. test-python.yml, test-node.yml): pytest for Python tools, vitest and Cypress for TS tools. Tests run as they do in the original repos, including tests with mocked tools. Only tests that need a real running service are skipped, via test selection in the root CI (e.g. pytest markers or spec paths), not deleted from packages.
- One shared Python version matrix for all Python tools (intersection of current ranges), pinned explicitly in every test command. bagel-cli jobs check out submodules.
- A package's tests run when files in that package change, or when shared root files change (lockfiles, root configs, shared workflows and actions, deploy/, testdata/).
- Upstream checks are ported or dropped per the inventory (Phase 1).
- No required status checks yet (see note in the developer docs step).
- No cross-tool tests yet.

Releases and publishing:

- release-please with one combined release PR; per-tool versions, changelogs, tags and GitHub Releases. *(Revised 2026-11-09, Gate 3 review.)* Manifest seeded from each tool's last tag; bootstrap-sha verified with git cat-file -t. Python tools use a release type that does not write versions (hatch-vcs reads the tag); JS tools use the node type.
- Release PRs are opened with the org bot app token so they trigger CI.
- The literal BEGIN\_COMMIT\_OVERRIDE marker never appears in PR templates or descriptions (escape it as BEGIN\_COMMIT\_OVERRIDE); release-please reads it anywhere in a merged PR's description.
- Publishing workflows at root, triggered per released component (from release-please's outputs in the release workflow; nightly images with dorny/paths-filter): Docker images (version tag + latest), nightly Docker images on push to main for changed packages only, PyPI release of bagel, static site deploys for annotation-tool and query-tool. Targets come from repository variables (IMAGE\_REGISTRY, IMAGE\_NAMESPACE, PyPI repository URL, site deploy on/off), so the same workflows publish to ghcr and TestPyPI during validation and to Docker Hub and PyPI in production.
- Docker images are built from each package folder with its existing Dockerfile. Each image's file listing is compared with the upstream image, using a clean checkout. bagel-cli's nightly image gets the one change needed to read its version from the monorepo tags, and its build checks out submodules. query-tool image checks set NB\_API\_QUERY\_URL.
- No registry, namespace or deploy targets are hardcoded in workflows; they come from repository variables.

Mirror to the old repos (during the trial) *(Revised 2026-11-09, mirror decision.)*:

- Source: monorepo main, first-parent history. Targets, data repos first: deploy/ to recipes, testdata/ to neurobagel\_examples, packages/\<dir>/ to the tool repo (names.yaml). The owner comes from the repository variable MIRROR\_OWNER; while it is unset, the mirror does nothing.
- Transform: a plain copy of the folder. The only change: each names.yaml symlink becomes a gitlink to the data repo's mirror commit as of that monorepo commit (at the import these equal the upstream submodule pins, so the transformed import tree equals old main exactly; checked at Gate 3 review).
- Mirror branch: monorepo-mirror in each old repo, append-only, never force-pushed after switchover. One commit per monorepo commit that changes the transformed tree (so a deploy/ change also bumps the gitlinks in api and query-tool). Each commit keeps the original author, date and message, with (#N) rewritten to (neurobagel/neurobagel#N), plus a trailer Monorepo-Commit: neurobagel/neurobagel@\<sha>. Multi-tool merges become one commit per affected repo.
- Starting point (anchor): the old main commit in migration/import-sources.txt, paired with the monorepo import commit of that repo. No separate record. Before its first commit, the mirror checks that the transformed tree at the anchor equals the old tree.
- Pull requests: each run opens or updates one PR monorepo-mirror to main per old repo. Old CI runs on it (every old test workflow triggers on pull\_request).
  - Before switchover (the old repo carries no mirror ruleset): the PR is a draft. The mirror writes only the branch: never main, never tags. A rehearsal rebuild resets the branch (input reset).
  - After switchover, once the maintainer has set the repository variable MIRROR\_MERGE=true: once all checks on the PR head pass, the mirror fast-forwards old main to it (bot bypass), and GitHub marks the PR merged. The next change opens a new PR. If checks fail, the PR stays open and later commits stack on it, and the mirror run fails (see Report back). Tags: for each new \<prefix>-vX.Y.Z tag, the mirror pushes vX.Y.Z to the mirror commit of the tagged commit (or the newest mirrored commit before it), after main contains it.
- Guards: the mirror merges and tags only when BOTH the repository variable MIRROR\_MERGE is true (set by hand after switchover, never in the rehearsal repository) AND the old repo carries a ruleset restricting updates of main (set only at switchover). The ruleset alone is not enough: the old repos already have other rulesets, and an unrelated "restrict updates" rule must not start merges into a live repo. *(Revised 2026-11-10: explicit merge switch.)* If old main contains a commit the mirror did not make, the mirror stops. Recovery after porting that commit: input adopt=\<repo>=\<sha> makes the next mirror commit take that head as a second parent, so the PR fast-forwards again.
- Report back: a commit status mirror/\<tool> on the monorepo commit, from the PR's checks. No issues are opened. When old CI fails or the mirror hits an error, the mirror run fails: a mirror badge in the root README shows it, and if the repository secret MIRROR\_DISCORD\_WEBHOOK is set, a message with the run link goes to Discord. *(Revised 2026-11-10: no issues; failing run, badge, optional Discord webhook.)*
- Workflow .github/workflows/mirror.yml: on push to main, nightly, and workflow\_dispatch (inputs dry\_run, reset, adopt). One concurrency group. Bot app token scoped to the seven old repos (Contents, Pull requests and Workflows write; mirrored commits change .github/workflows/).
- Mirror check: a job on monorepo PRs runs the transform as a dry run on the PR head. It fails on anything the mirror cannot map (a symlink or gitlink leaving a package that is not in names.yaml).

Rules for working in the monorepo during the trial (in DEVELOPING.md and the PR template) *(Revised 2026-11-09, mirror decision.)*:

- Packages stay self-contained: each builds and tests from its own folder with its own lockfile and configs. No npm or uv workspace with a root lockfile, no imports across packages, no root-context Docker builds, no root config replacing a package config (adding root configs is fine).
- Package .github/, .gitmodules and configs are live (old repos' CI and setup). A change to a package's build or CI updates its package workflows in the same PR.
- Packages reach shared data only through the names.yaml symlinks (the mirror check enforces this).
- No renaming of package folders or tag prefixes, and no history rewriting on main.
- Red old-repo CI on a mirror PR is a must-fix (red mirror badge, Discord message), fixed in the monorepo; it does not block monorepo merges.
- Changes from the old repos come in only by porting (git format-patch | git am -3 --directory=packages/\<dir>), described in DEVELOPING.md.

Repository settings (documented in migration/, applied by a maintainer):

- Merge commits and squash merges both allowed; squash is the default, with the PR title as the commit message. Rebase merges off.
- Branch protection on main: PR review required, no required status checks for now.
- Secrets are org-level and already exist; confirm the new repo has access.
- Labels needed by release-please and existing issue workflows.

## Migration steps

Phases 0-3 happen locally. Phase 4 is a repeatable rehearsal in a scratch repository while the old repos stay live. Phase 5 is the switchover: lock the old repos, rebuild from scratch, first push to neurobagel/neurobagel, start the mirror. Phase 6 is the trial; it ends with keeping the monorepo or switching back. *(Revised 2026-11-09, mirror decision.)*

### Working rules for every phase

- Each phase ends with a gate. At a gate: run every listed check, write the results (commands, output summaries, counts) to migration/RUN\_NOTES.md, report to the maintainer, and stop. Do not start the next phase without an explicit go from the maintainer.
- A gate passes only if every check passes or the maintainer explicitly accepts a listed deviation. Never weaken, skip or rewrite a check to make it pass.
- Until the switchover push (Phase 5): all fixes go into import.sh, commit-rewrites.yaml, a patch, a script or verify.sh, then the pipeline is rerun from scratch. Never hand-edit the assembled repo. This includes anything changed while trying out the rehearsal repository.
- Never push to, open PRs on, or change settings of the upstream repos yourself. Exceptions, from Phase 4: the mirror workflow (bot) pushes the monorepo-mirror branch and opens its PR; in Phase 5 the maintainer runs switchover.sh. *(Revised 2026-11-09, mirror decision.)*
- Never merge a release PR, publish to Docker Hub or PyPI, or switch repository variables to production targets without explicit maintainer approval.
- When a decision is not covered by this plan, ask instead of guessing, and record the answer in RUN\_NOTES.md.
- RUN\_NOTES.md also records anything unexpected, every change to package code and why, and any manual step.

### Phase 0: Prepare

1. Set up the agent environment (see Agent environment) and confirm access: gh authenticated with rights to create neurobagel/neurobagel; neurobagel/neurobagel does not exist yet or is empty; org secrets and bot app can be granted to it.
2. Create a local working directory with migration/ and an empty RUN\_NOTES.md.

Gate 0: environment works, access confirmed, open questions in Decisions listed for the maintainer.

### Phase 1: Inventory and baseline (read-only)

3. Per repo, write one table to migration/inventory.md: workflows, hooks, bots, deploy targets and test commands, each marked keep, port or drop. Known items include lychee and linkspector link checks, CITATION.cff validation (drop), Scorecard, stale, issue-to-project, handle\_external\_pr, example-diff, husky post-merge hooks, pre-commit.ci.
4. Run each repo's full documented check set upstream, not only what CI runs. Write to migration/baseline.md: test counts per suite and Python version, existing failures (see Known upstream issues), and which tests are service-dependent and will be skipped.

Gate 1: maintainer confirms keep/port/drop, the baseline, the service-dependent test list and the Python matrix (incl. 3.11).

### Phase 2: Import history (local)

5. Write migration/names.yaml and migration/import.sh. import.sh takes the target directory or remote as an argument and, for each tool repo: fresh clone, git filter-repo (--to-subdirectory-filter packages/\<dir>, --tag-rename '':'\<prefix>-', message callback rewriting (#N) to (neurobagel/\<repo>#N) and applying the commit title rewrites), merge with --allow-unrelated-histories. It then copies recipes (HEAD of main) to deploy/ and neurobagel\_examples to testdata/; replaces those gitlinks with relative symlinks; keeps the gitlinks of communities, pipeline-catalog and bids-examples (paths move with filter-repo, pins unchanged); declares these three in the root .gitmodules; keeps package .gitmodules as dead code; initializes submodules last; and writes migration/tag-map.txt.
6. Commit title rewrites: for commits since each tool's last tag with non-conventional titles, derive the conventional type from the PR's release label (via the GitHub API) and store the result in migration/commit-rewrites.yaml, which import.sh applies. List unclear cases for the maintainer.
7. Write the history part of migration/verify.sh: commit counts per tool with git rev-list --count (not git log -- path), tag counts including the no-branch query-tool tags, sample PR links point to original repos, symlinks resolve, all three submodules initialize at their upstream pins, package files identical to upstream apart from the gitlink changes.
8. Run import.sh from scratch twice; both runs must give the same file tree and tags.

Gate 2: history checks pass; maintainer reviews tag-map.txt and commit-rewrites.yaml and resolves unclear rewrites.

### Phase 3: Monorepo setup (local)

9. Author the remaining changes as ordered commits, one concern each, exported to migration/patches/ with git format-patch:
   1. Root LICENSE (from bagel-cli), README, migration/ docs.
   2. hatch-vcs settings for prefixed tags in each Python package.
   3. Root uv workspace. *(Revised 2026-11-09: dropped, see Decisions.)*
   4. pre-commit hooks, PR title check and release preview, check-unchanged.sh (local only, no CI workflow), root dependabot.yml. *(Revised 2026-11-09, Gate 3 review and mirror decision.)*
   5. Root CI: reusable workflows, path-filtered tests on the pinned shared Python matrix, skipping only service-dependent tests; ported upstream checks per the inventory.
   6. release-please config and manifest.
   7. Publishing workflows (Docker release + nightly, PyPI, static sites), building each image from its package folder, plus the bagel-cli nightly change; a manual (workflow\_dispatch) trigger that builds and pushes images to the configured registry with a non-release tag, for validation.
   8. Developer docs (root DEVELOPING.md; was migration/, revised at the Gate 3 review): setup, running tests, PR title format and merge policy, how releases work, the trial rules and how the mirror works (see Requirements), how to port a PR from an old repo, a note that release PRs only update on new releasable commits, a note that "Re-run jobs" reuses the old base (close and reopen or push instead), and a note on required checks: none for now; when added, use one always-running aggregator job as the only required check, because path-filtered jobs that are skipped never report and block merging. Plus the repository settings, and migration/settings.sh (gh api) to apply them.
   9. README monorepo sections, written last.
   10. Mirror: tools/mirror.py, .github/workflows/mirror.yml and the mirror check job; migration/switchover.sh \<owner> \<bot-app-id> [--undo] (ruleset on all branches and tags with the bot app as the only bypass, disabling the old release and publishing workflows listed in migration/old-repos-disabled.txt, with a dry-run mode); migration/sync-to-old-repo.sh is removed. *(Revised 2026-11-09, mirror decision.)*
10. Write migration/migrate.sh: import.sh, then git am migration/patches/\*, then verify.sh. It does not push. It writes release-please's bootstrap-sha from the import (not hard-coded in a patch), so refreshes need no patch edit. *(Revised 2026-11-09, mirror decision.)* *(Revised 2026-11-09: between import.sh and the patches, migrate.sh commits the current migration/ directory (plan without the agent environment section, scripts, records, developer docs, settings.sh, patches) as one generated commit, because these files keep changing until Phase 4 and cannot live in a fixed patch. Patch 1 is then LICENSE and README only, and patch 8 is empty.)*
11. Extend verify.sh (each check labelled LOCAL or CI): check-unchanged.sh passes; uv sync and npm ci in each frontend work; test counts match the baseline; pre-commit passes on all files without changing any; each Python package reports the version of its latest tag; the bagel wheel and sdist contain communities and pipeline-catalog as real files; each Docker image builds locally and its file listing matches the upstream image (clean checkout); README commands work word for word in a fresh clone. S11, local mirror round trip: mirror the assembled monorepo into local copies of the seven old repos and check the anchor invariant; the first mirror commits differ from old main only by the allowlisted edits; hatch-vcs in the mirrored Python repos reports the latest old tag; each old repo's documented test commands pass in the mirrored copy; a synthetic fix, a deploy/ change and a release tag give the expected commits, gitlink bump and vX.Y.Z tag; a rerun changes nothing; a foreign commit on old main stops the mirror and adopt\_old\_head recovers. *(Revised 2026-11-09, mirror decision.)* Add a deliberate-failure test for each guard (e.g. a changed protected file, an invalid dependabot config, a non-conventional PR title) to prove it fires. *(Revised 2026-11-09, Gate 3 review: the PR title check is an action and is checked on GitHub in Phase 5.)*
12. Check release-please locally: run its parser (or the CLI in dry-run mode) on the assembled history and on a synthetic multi-tool merge, and confirm the proposed versions and changelog entries per tool.

Gate 3: migrate.sh runs from scratch with no manual edits and verify.sh passes; maintainer reviews the patch series, check-unchanged allowlist and RUN\_NOTES.md.

### Refresh (before every rehearsal rebuild and at switchover)

- Fresh clones (automatic in import.sh).
- Regenerate commit-rewrites.yaml for commits merged since the last run (gen-commit-rewrites.py); the maintainer resolves unclear ones.
- Re-measure the baseline test counts (step 4) where upstream tests changed.
- Diff each old repo's .github/ since the inventory, to catch new workflows to port, or to disable at switchover.
- If upstream changed a file a patch touches, rebase the patch series and re-export it.
- Run migrate.sh; verify.sh must pass.

### Phase 4: Rehearsal (repeatable; old repos stay live)

13. neurobagel/testplace exists (empty; local clone at testplace/ next to the other repos). The maintainer runs settings.sh neurobagel/testplace --rehearsal --apply (no branch protection; variables at safe targets: ghcr registry and namespace, TestPyPI, site deploys off, MIRROR\_OWNER=neurobagel) and grants org secrets and the bot app. The bot app also needs Contents, Pull requests and Workflows write on the seven old repos.
14. Refresh, with migrate.sh assembling into testplace/. The maintainer pushes main and all tags to the rehearsal repository (tell the maintainer exactly when to push; later rebuilds are force-pushed).
15. Validate on GitHub (no production publishing):
    - A PR touching one package runs only that package's tests; a PR changing a shared workflow runs all; the PR title check rejects a non-conventional title; the release preview job summary shows the per-tool entries of a multi-tool PR.
    - release-please (bot token) opens one combined release PR and CI runs on it. Check the proposed versions and changelogs per tool. It may be merged in the rehearsal to see the tags, GitHub Releases and publishing jobs run against ghcr and TestPyPI.
    - The manual image workflow builds and pushes every image to ghcr with the non-release tag; file listings match upstream. A push to main builds nightly images to ghcr only for changed packages.
16. Mirror rehearsal against the real old repos (branch and draft PR only; nothing on their main, no tags):
    - Dry run, then the first real run: each old repo gets the monorepo-mirror branch, based on its import-source commit, and a draft PR. Old CI runs on it and must pass. A draft PR can conflict with changes merged upstream after the rehearsal's import; that is expected, and the next refresh resolves it.
    - Exercise: a merged rehearsal PR appears as a new mirror commit and its old-CI result comes back as a mirror/\<tool> status; a multi-tool merge; a deploy/ change bumps the gitlinks; a merged release PR adds no tag to the old repos; red old CI fails the mirror run (and posts to Discord if the webhook secret is set); a rerun changes nothing.
17. Repeat steps 14-16 as often as wanted (reset the mirror branches after each rebuild). Whatever is worth keeping from trying out the rehearsal goes into the pipeline.

Gate 4: all checks pass, including green old CI on every draft mirror PR (a PR whose CI cannot run because of conflicts with newer upstream changes passes only after a refresh); the maintainer picks the switchover date.

### Phase 5: Switchover

18. Announce. The maintainer runs migration/switchover.sh neurobagel \<bot-app-id> (dry run first, then --apply): ruleset on each of the seven old repos (all branches and tags, bot app as the only bypass); old release and publishing workflows disabled (list kept in migration/old-repos-disabled.txt); old repos removed from pre-commit.ci; Dependabot security updates off there. This replaces a merge freeze: nothing can land in the old repos from now on except through the mirror. Unset MIRROR\_OWNER in the rehearsal repository.
19. Refresh from the locked state.
20. Maintainer creates neurobagel/neurobagel (empty, no initial commit), with variables as in step 13, org secrets and the bot app; pushes main and all tags (tell the maintainer exactly when); runs settings.sh neurobagel/neurobagel --apply.
21. Mirror: run with reset, so the branches start at the new anchors (the locked old main). Dry run first; the maintainer reviews the job summary. Then the real run, still without merging: draft PRs only. Once old CI is green on them, the maintainer sets the repository variable MIRROR\_MERGE=true and reruns the mirror. *(Revised 2026-11-10: explicit merge switch.)* Each mirror PR is now a fast-forward of old main; when its checks pass, the mirror fast-forwards main.
22. Maintainer switches the repository variables to production targets (Docker Hub, PyPI, site deploys on). Confirm the next nightly lands on Docker Hub under the unchanged image names.
23. Port open old-repo PRs to the monorepo (DEVELOPING.md) and close the old ones with a pointer. Delete the rehearsal repository. Announce that development continues in neurobagel/neurobagel.

Gate 5: the first mirror PR in each old repo merged by fast-forward with green old CI; the first production nightly confirmed.

### Phase 6: Trial (about 3-4 months)

24. Development, review and releases happen in the monorepo under the trial rules (Requirements).
25. When the maintainers decide to release, merging the release PR must create a GitHub Release and \<component>-v\<version> tag per released tool, publish images to Docker Hub with version tag and latest, publish bagel to PyPI, deploy the sites, and, once the mirror PR merges, add vX.Y.Z to the old repo. Check each.
26. Red old CI on a mirror PR is fixed in the monorepo (the mirror run fails until then).

Gate 6: first production nightly confirmed; first release confirmed, including the old-repo tag.

### End of trial

27. Keep the monorepo: stop the mirror (unset MIRROR\_OWNER, remove mirror.yml and tools/mirror.py); archive the old repos or leave them locked with their README pointer; remove migration/ and images-validation.yml, keeping names.yaml, tag-map.txt, commit-rewrites.yaml and the scripts in tools/; the Later items blocked by the trial rules become possible.
28. Or switch back:
    1. Check the last mirror PR is merged at monorepo HEAD with green old CI.
    2. Stop the mirror (unset MIRROR\_MERGE and MIRROR\_OWNER).
    3. Switch off monorepo publishing (variables).
    4. Re-enable the workflows in migration/old-repos-disabled.txt and re-add pre-commit.ci.
    5. Remove the rulesets.
    6. Port open monorepo PRs back (git format-patch --relative=packages/\<dir> | git am -3 in the old repo).
    7. Archive the monorepo.

    Versions continue from the mirrored vX.Y.Z tags. Before switching back, check what auto reads as the last version. If it needs GitHub Releases, create them for the mirrored tags (gh release create).

### Staged switchover (fallback, only if one tool cannot be locked with the others)

The tool is left out (names.yaml switch: later; import.sh skips it; git am --exclude skips its package patches; its root config entries stay but do nothing, which needs a release-please test with a missing package path). Its old repo stays fully live, including releasing and publishing. At its own switchover: lock it, import its history into the live monorepo on a branch with its package patches (an import.sh --add mode), set its manifest version to its latest tag, merge with a merge commit, and start mirroring it from the new import commit. Built only when needed.

## Risks and fallbacks

- uv workspace: one uv.lock means one version of each dependency across the Python tools. No known conflicts; verify in Phase 3.
- npm workspace with React 18 vs 19 and MUI 6 vs 7: hoisted shared libraries can load the wrong React, causing duplicate-React runtime errors. Avoided by not using an npm workspace until React versions are aligned, at the cost of two lockfiles and two installs.
- Symlinks: need core.symlinks on Windows. Docker builds don't follow symlinks out of the build context; this is fine because no image uses deploy/ or testdata/. Recheck if images are later used for dev environments or test stacks. *(Revised 2026-11-09, Phase 3: query-tool's image build runs tsc over its Cypress specs, one of which imports from neurobagel\_examples, so the build fails on the dangling symlink. The image workflow replaces each package's symlinks with copies of their targets in the build context before building, matching upstream's context, which held the submodule contents. No package change.)*
- Old-repo CI drifts from monorepo CI (upstream's wider Python ranges, bagel-cli's --upgrade), so mirror PRs can go red when monorepo CI is green. Mitigated by the mirror/\<tool> status, the failing mirror run (README badge, Discord) and the trial rule that red old CI is a must-fix. *(Revised 2026-11-09, mirror decision.)*
- Draft mirror PRs during the rehearsal run CI in the live old repos and show up there; their description says not to merge before switchover, and the mirror cannot merge them (no ruleset). *(Revised 2026-11-09, mirror decision.)*

## Renaming later

Package directories and tag prefixes may be renamed after migration, but not during the trial (the mirror maps them through names.yaml). The rename mechanism is not built now, but nothing done now may make it harder. *(Revised 2026-11-09, mirror decision.)*

Rules for now:

- migration/names.yaml is the single map of repo, directory, tag prefix and artifact names. Scripts read it; nothing else invents names.
- import.sh writes tag-map.txt, so every tag can be re-derived from its original repo tag and commit.
- release-please sets component (tag prefix) explicitly per package path, so directory and tag prefix change independently.
- Code inside a package never refers to its own directory name. Links to deploy/ and testdata/ are relative symlinks.
- Package names appear only in a known set of files: release-please config, CI path filters, dependabot.yml, workspace config, pre-commit config, names.yaml, the repository list in mirror.yml, old-repos-disabled.txt, and the hatch-vcs tag settings in each Python package's pyproject.toml. Use globs (packages/\*) where the tool allows.
- Published artifact names (PyPI, Docker) are independent of directory and tag names.

Later procedure (to be scripted when needed):

- Directory rename: git mv, then update the known files. Per-file history follows with git log --follow.
- Tag prefix rename: create new tags at the same commits from tag-map.txt, update release-please config and the hatch-vcs tag settings of the affected package. Keep old tags as aliases to avoid breaking existing links.
- Monorepo rename: rename on GitHub (old URLs, clones and API calls redirect as long as the old name is never reused). Then update: PyPI trusted publisher config (if used; it is tied to the repo name and publishing fails otherwise), Docker Hub / static site / other third-party integrations tied to the repo, repository URLs in pyproject.toml, package.json and Docker labels, README badges and links, docs, and the pointers in the old repos' READMEs. Keep the monorepo name out of code so this list stays short.

## Later (not part of this migration)

Items marked *(after the trial)* would break the mirror (root lockfiles, shared packages consumed by path, root-context Docker builds, root configs replacing package configs). They wait until the trial ends with keeping the monorepo, unless they also get a form the mirror can copy. *(Revised 2026-11-09, mirror decision.)*


- Move documentation into docs/.
- Cross-tool workflows from recipes and neurobagel\_examples (recipes compatibility.yaml, test\_setup.yml, test\_fullstack\_e2e.yml and its test-setup action; neurobagel\_examples make\_api\_responses.yml): files stay in deploy/ and testdata/ but are not wired to CI during migration; redo them properly, together with the global integration suite. *(Added 2026-11-09, Gate 1.)*
- A single link checker for the whole monorepo, replacing the per-package linkspector (api) and lychee (annotation-tool) configs that the central link-check workflow runs during migration. *(Added 2026-11-09, Gate 1.)*
- React version alignment: align React and MUI major versions across annotation-tool and query-tool, then introduce the root npm workspace (root package.json with workspaces, one package-lock.json, root dependabot entry updated). *(after the trial)*
- Required status checks via one aggregator job. Together with: one ci.yml instead of the five per-tool workflows: a `changes` job (dorny/paths-filter) decides which tools changed and calls the reusable test workflows, so the path rules live in one place and the aggregator job sees every tool's result (skipped jobs inside one workflow report a status; workflows skipped by `on: paths:` do not). Done this way in the neurobagel/develop test run (.github/workflows/ci.yml). *(Added 2026-11-09, Gate 3 review.)*
- Build the images on PRs (no push) for tools whose image inputs changed, plus a smoke test for query-tool (start the container with NB\_API\_QUERY\_URL and expect HTTP 200 on port 5173). Today image builds run only after merge (nightly, release), so a broken build is found late; Phase 3's query-tool build failure (tsc over a Cypress spec importing through a dangling symlink) would have shown on the PR. neurobagel/develop did this for query-tool (ci.yml, query-tool-image job). *(Added 2026-11-09, Gate 3 review.)*
- bagel-cli package check on PRs: build the wheel and check it contains files under bagel/communities/ and bagel/pipeline-catalog/ (submodules bundled into the wheel; a submodule bump or checkout mistake could ship them empty). About 10 lines; neurobagel/develop had it (ci.yml, bagel-cli-package job). Migration verify.sh S7 checks this only locally. *(Added 2026-11-09, Gate 3 review.)*
- actionlint (and shellcheck for any scripts) on PRs, e.g. as a pre-commit hook run by pre-commit.ci. During migration it runs only locally in verify.sh, so after migration nothing checks workflow edits. *(Added 2026-11-09, Gate 3 review.)*
- A task runner for developers (just/justfile, as in the neurobagel/develop test run): e.g. `just test <tool>`, `just build <tool>`, `just lint`, wrapping the per-tool commands now in each README's "Working in the monorepo" section. *(Added 2026-11-09, Gate 3 review.)*
- One codespell configuration for the whole repository, replacing the five per-package .codespellrc files (and the hook excludes that repeat their skip lists). *(after the trial)* *(Added 2026-11-09, Gate 3 review.)*
- Transfer open issues from the old repos; decide whether to archive them.
- A single root citation file for the monorepo.
- Local full-stack dev environment from locally built containers.
- Single global integration test suite (cross-tool, contract and end-to-end), replacing the skipped service-dependent tests and the per-tool mocks of other tools.
- Shared schema and type packages, shared root linter/formatter configs, frontend dependency convergence. *(after the trial)*
- Schema versioning.
- Replace bagel-cli's data submodules (communities, pipeline-catalog, bids-examples) with a data fetching approach.

## To consider (from the neurobagel/develop test run; not adopted now because they conflict with a decision of this plan)

- *(after the trial)* Root-context image builds: build each image with the repository root as context and tools/\<tool>/Dockerfile, with an allowlist ignore file next to each Dockerfile (Dockerfile.dockerignore, read by BuildKit). Removes the symlink materialization step in docker-build.yml and lets images use deploy/ and testdata/ directly. Conflicts with "each image builds from its own package folder with its existing Dockerfile"; needs Dockerfile changes (COPY paths) in every image package.
- bagel-cli image from the CI-built wheel (during the trial, together with the package's own nightly workflow): see Quick follow-up fixes. In neurobagel/develop the nightly built the wheel once (with submodules, hatch-vcs version from tags), uploaded it as an artifact and the image installed exactly that wheel, so .git and the version build argument are not needed. A package (Dockerfile) change.
- api integration tests in CI against the test graph (docker compose up test\_graph, wait for "FINISHED UPLOADING DATA", then pytest -m "integration or not integration"), as neurobagel/develop's test-python.yml did with a needs-graph input. Conflicts with skipping service-dependent tests until the global integration suite; could be the first piece of that suite.
- Per-tool Python matrices (neurobagel/develop: api and federation-api 3.10-3.13, bagel-cli 3.11-3.14 with --upgrade) instead of one shared matrix. Conflicts with the shared-matrix decision; worth revisiting when the tools' supported ranges are next reviewed, since the shared 3.12-3.13 tests less than each tool supports.
- Folder name tools/ instead of packages/ (neurobagel/develop). Purely naming; possible later with the rename procedure.
- Full-stack local environment and tests from locally built images: stack/ (a dev copy of recipes), e2e/ (Cypress full-stack tests against two local nodes), examples regenerated from a local deployment, driven by just recipes (just dev, just e2e, just examples). Belongs with "Local full-stack dev environment" and the global integration suite under Later.
- Running pre-commit in GitHub Actions (pre-commit/action) instead of pre-commit.ci. pre-commit.ci was chosen at Gate 1; GitHub Actions would allow the hooks that pre-commit.ci skips (docker-compose check, frontend hooks needing node\_modules).
- A bootstrap-sha check in CI (git cat-file -e). Only matters until the first release; verify.sh checks it locally.

## Quick follow-up fixes (right after migration)

- Build bagel-cli's Docker image from the wheel built in the same CI run, instead of needing .git in the build context; the Dockerfile checks that exactly one wheel is present.

## Known upstream issues (record, do not fix during migration)

- recipes: the federation API is connected to another node's network, so graph resolves to both graphs. Fix: attach the federation API to each node's network instead.
- query-tool: the compose test profile is broken (init\_data undefined, local\_nb\_nodes.json missing).
- query-tool: the image entrypoint exits without NB\_API\_QUERY\_URL.
- bagel-cli fails at import on Python 3.11 with its locked dependencies; upstream CI hides this with --upgrade.
- annotation-tool component tests flake about 1 run in 35 (Vite re-optimizing dependencies mid-run). Candidate fix: set optimizeDeps to cover the Cypress specs.
- query-tool e2e flake: Form.cy.ts "Selects different nodes in the nodes field" fails when a MUI tooltip still covers the first option (`cy.click()` covered by another element). In this container it fails often: 2 of 3 runs of the monorepo README block and 4 of 5 runs of Form.cy.ts on an unchanged upstream clone (Gate 3 review); upstream CI on GitHub has been green on it recently. It passed in all earlier gate runs. Candidate fix: close the tooltip or wait for it before clicking. *(Added 2026-11-09.)*
- External links already failing: api's SNOMED link (and the docs' OSF link, once docs move in).

