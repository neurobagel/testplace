# Run notes

## Phase 0: Prepare (2026-11-09)

Checks:
- Toolchain (from existing project_temp/.tools, sourced via project_temp/tools-env.sh, not modified): git 2.39.5, git-filter-repo, just 1.59, pre-commit 4.7, actionlint 1.7.12, twine 7.0, node 20.20.2 / npm 10.8.2, uv 0.13.7, jq 1.6, docker CLI 29.9.1 + buildx 0.38 + compose 5.6 -> host Podman 6.1.4. `docker run alpine` OK.
- Python via uv: 3.11.2 (system), 3.12.16, 3.13.18, 3.14.10 all resolve (non-system ones download into ephemeral $HOME).
- Supported ranges: api >=3.10,<3.14; federation-api >=3.10,<3.14; bagel-cli >=3.11,<3.15 -> intersection 3.11-3.13.
- GitHub: `gh` NOT authenticated. Public REST API works (60 req/h unauthenticated). HTTPS clone works (`git ls-remote https://github.com/neurobagel/api.git`). SSH fails (no keys in container).
- All upstream repos reachable (api, federation-api, annotation-tool, bagel-cli, query-tool, recipes, neurobagel_examples, communities: HTTP 200).
- neurobagel/neurobagel: HTTP 404 (does not exist, or is private).
- Local neurobagel/: `git init`'d, branch main, no commits, origin = git@github.com:neurobagel/neurobagel.git. Local git identity set to Claude <noreply@anthropic.com>.
- Not verifiable from here (no gh auth): rights to create neurobagel/neurobagel, org secrets / bot app grant.
- Update: gh authenticated as surchs with a fine-grained PAT (token file deleted after login; login lives in ephemeral $HOME). Rate limit 5000/h. PR label reads work. neurobagel/neurobagel still 404 with the token (does not exist, or token cannot see it).

Gate 0 decisions (maintainer, 2026-11-09):
1. Working copy of migration/ lives in monorepo-migration/migration/ (outside the assembled repo); it enters neurobagel/ via the first patch (step 9.1). neurobagel/ is only ever assembled output.
2. If tools must be reinstalled, they go into monorepo-migration/.tools (not project_temp/.tools).
3. Learnings from this run are kept in monorepo-migration/migration-learnings.md.
4. neurobagel/neurobagel already exists and is private (hence 404). Fine until Phase 4; emptiness to be confirmed by the maintainer before the push. Private-repo implications to check by Phase 4/5: branch protection/rulesets and Actions minutes depend on the org plan; ghcr package visibility.
- Update: neurobagel/neurobagel is now public; verified empty (API 409 "Git Repository is empty", ls-remote returns no refs). Your account has admin rights on it. Gate 0 passed.

## Phase 1: Inventory and baseline (2026-11-09)

- Fresh clones of all 7 repos in monorepo-migration/clones/ (HTTPS, --recurse-submodules). HEADs and last tags in inventory.md.
- Inventory: migration/inventory.md (workflows, hooks, bots, deploy targets, test commands; keep/port/drop; open items marked "?").
  Sources: workflow files, .autorc, .pre-commit-config.yaml, .husky, dependabot.yml, Actions run history (gh api .../actions/runs), Pages API, Docker Hub tags, DNS/HTTP headers of the two sites.
- Baseline: migration/baseline.md. Scripts and logs in monorepo-migration/baseline/.
  - api 184 (+6 integration with graph = 190) on 3.10-3.13; f-API 111 on 3.10-3.13; bagel-cli 210 on 3.12-3.14 locked, import error on 3.11 locked, 210 on 3.11-3.14 with --upgrade.
  - pre-commit: all three Python repos pass, no modifications.
  - annotation-tool: typecheck/lint/format/codespell/lychee pass; vitest 263; Cypress e2e 24, component 185.
  - query-tool: typecheck/lint/format/codespell pass; Cypress component 91, e2e 41.
  - api linkspector: only the known SNOMED link fails.
  - Network-off run (unshare -rn) to separate service-dependent from internet-dependent tests.
- Unexpected:
  - annotate.neurobagel.org and query.neurobagel.org are both GitHub Pages sites (one per repo); a single monorepo can only serve one Pages site.
  - api/f-API Dockerfiles use the package's own uv.lock (uv export --frozen); conflicts with a single root uv.lock.
  - annotation-tool has build_docker_on_release.yml but no Dockerfile (last run failed); no annotation-tool image exists on Docker Hub.
  - neurobagel/bagelcli on Docker Hub (nightly, vX.Y.Z, latest) is a published artifact missing from the plan's list.
  - bagel-cli release image installs bagel from PyPI, so it must run after the PyPI upload.
  - Upstream CI starts api's test graph via submodules; api integration tests pass locally with the graph (all 4 versions).
  - Tool repos have CodeQL default setup enabled (repo setting) and pre-commit.ci (Python repos).
  - linkspector's docker image on ghcr returned 403; ran via npx in the cypress image as non-root instead.
- Throwaway side effects (clones only): bagel-cli uv.lock rewritten by --upgrade run, restored with git checkout; .env files written in the frontend clones for Cypress.

### Gate 1 answers (maintainer, in inventory.md, 2026-11-09)
- add_iss2project: drop.
- Codecov: port (incl. annotation-tool merge-coverage).
- linkspector: port, ideally as a central root workflow.
- Static sites: annotation-tool and query-tool both build for Netlify (like the current beta-annotate deploy); query-tool keeps injecting the plausible script. No GitHub Pages from the monorepo.
- query-tool updated_examples: port, PR targets testdata/ in the monorepo.
- recipes: auto release dropped in the monorepo; deploy/ is synced (copied) to the old recipes repo for now. compatibility/test_setup/test_fullstack_e2e: dropped from CI, files kept.
- neurobagel_examples make_api_responses: dropped from CI, files kept; listed under "Later" in the plan.
- Link checks: one central root workflow running each package's existing checker with its own config (api linkspector, annotation-tool lychee). A single monorepo-wide checker is listed under "Later" in the plan.
- Netlify: maintainer creates the two production Netlify sites (own site-ID secrets) and moves the annotate/query DNS at go-live. The existing Netlify job (NB_GOOGLE_APPS_SCRIPT_URL, NETLIFY_PROD_SITE_ID) is beta-annotate and keeps running.
- query-tool examples diff: port, compares against testdata/.
- recipes repo: deploy/ changes are pushed back to it, but no further releases are made there for now.
- Service-dependent tests: only the 6 api integration tests are skipped in CI; the 19 internet-dependent tests keep running.
- Python 3.11: decided in Phase 3 from the root uv.lock (keep 3.11 if bagel-cli imports on it, else 3.12-3.13).
- pre-commit in CI: option A, pre-commit.ci on the monorepo (maintainer installs the app). Root config sets a conventional autoupdate commit message (chore: ...) and `ci: skip` for hooks that need Docker or node_modules (docker-compose-check, frontend typecheck/eslint/prettier); those are covered by the frontend CI workflows.
- Gate 1 passed (all keep/port/drop decisions, baseline, service-dependent list resolved; Python 3.11 deferred to Phase 3 by decision).

## Phase 2: Import history (2026-11-09)

Files (monorepo-migration/migration/): names.yaml, import.sh, import_helper.py (filter-repo as a library + names parsing), gen-commit-rewrites.py, commit-rewrites.yaml, verify.sh (history checks H1-H10), outputs tag-map.txt and import-sources.txt.
Pinned tooling: git-filter-repo 2.47.0, PyYAML 6.0.3 (via `uv run --with`).

Implementation choices (within the plan):
- Commits created by import.sh (initial empty commit, 5 import merges, deploy/, testdata/, symlink + root .gitmodules commit) use identity Claude <noreply@anthropic.com> and a fixed date = newest upstream HEAD committer date, so reruns give identical hashes.
- import.sh takes a target directory (not a remote); it refuses a target with commits or files, and accepts an existing empty `git init` (keeps its remote config). It never pushes.
- import-sources.txt records the upstream commits imported (verify.sh checks against them).
- IMPORT_ALLOW_UNRESOLVED=1 allows development runs while commit-rewrites.yaml has unresolved entries (titles left unchanged, verify.sh H5 fails).
- Reference rewrite: every GitHub autolink reference `#N` in commit messages is qualified as `neurobagel/<repo>#N`, not only the `(#N)` title form. ~1949 refs qualified, ~1869 of them `(#N)`; the rest are "Fixes/Closes #N" (16) and "Merge pull request #N" (44) etc. Left unqualified they would autolink to unrelated monorepo issues/PRs. All 15 issues referenced with closing keywords are already closed (checked via API). Needs maintainer confirmation (Gate 2).

Commit title rewrites (gen-commit-rewrites.py, PR labels via gh api):
- 61 non-conventional titles since last tags: api 5, federation-api 22, annotation-tool 0, bagel-cli 33, query-tool 1.
- Rules (first matching label): pr-major/minor-breaking -> feat!, pr-minor -> feat, pr-patch/pr-bug-fix -> fix, pr-performance -> perf, pr-documentation -> docs, pr-tests -> test, pr-dependencies/dependencies -> build(deps), skip-release -> chore, _bot -> chore; pr-internal unresolved. Bracket prefixes ([FIX], [pre-commit.ci], ...) are stripped.
- Unresolved (2): federation-api #279 "Add OpenSSF Scorecard badge" and bagel-cli #721 "[MNT] Add OpenSSF Scorecard badge", both pr-internal.
- Note: bagel-cli #746 (pr-minor-breaking) -> feat!; stays a minor bump on 0.x only with release-please bump-minor-pre-major: true (Phase 3).

Results:
- import.sh run 1 (build/run1): 2384 commits, 156 tags, ~20 s. verify.sh: all checks pass except H5 "unresolved entries = 2" (expected until resolved).
  - H1 commits on main: api 512, federation-api 225, annotation-tool 382, bagel-cli 600, query-tool 656.
  - H2 tags: 26 + 21 + 34 + 38 + 37 = 156; every tag's package tree equals the upstream tag's tree.
  - H3 query-tool no-branch tags v0.10.2-next.0, v0.9.4, v0.9.5 present and off main.
  - H6 package trees at import identical to upstream; since import only the 5 gitlink->symlink type changes.
  - H7 deploy/ = recipes@e72cdb7 tree, testdata/ = neurobagel_examples@00bf8ee tree.
  - H8 5 symlinks resolve; H9 3 submodules at upstream pins, initialized, declared in root .gitmodules.
- Upstream submodule pins of recipes/neurobagel_examples in api, bagel-cli and query-tool all equal the data repos' HEAD (no version skew from copying HEAD).
- import.sh run 2 (build/run2): identical HEAD (cefdd030), tree, tags, tag-map.txt, import-sources.txt and worktree.
- import.sh into a pre-initialized repo with origin (build/run3): same HEAD; rerun refuses.
- Unexpected: none blocking. filter-repo removes `origin` in the clones (expected, clones are throwaway).

### Gate 2 answers (maintainer, 2026-11-09)
- tag-map.txt accepted.
- Label mapping accepted. pr-internal -> chore (federation-api #279, bagel-cli #721 resolved; generator rule updated). federation-api having nothing to release is fine.
- release-please: bump-minor-pre-major: true (breaking -> minor while on 0.x). Recorded in the plan's Decisions.
- Broader reference rewrite (all #N) accepted. Recorded in the plan's Decisions.
- Strict rerun (no IMPORT_ALLOW_UNRESOLVED): import.sh twice from scratch -> identical HEAD 6b77c59f, tags, worktree; verify.sh 52/52 PASS (61 title rewrites applied, 0 unresolved). Gate 2 passed.

## Phase 3: Monorepo setup (started 2026-11-09)

Findings before writing patches:
- release-please (17.11.2, action v5.0.0, read from source): with `skip-github-release` the action never calls createReleases, so no tags are created and no release outputs are set. Finding the previous release works from tags alone (backfillReleasesFromTags), so tags without GitHub Releases are enough for release PRs. A merged release PR left labelled `autorelease: pending` blocks new release PRs ("untagged, merged release PRs outstanding - aborting"), so whatever creates the tags must relabel it `autorelease: tagged`.
- uv workspace trial (scratch copy, hatch-vcs tag settings applied): root `uv lock` resolves (122 packages, requires-python >=3.11,<3.14), bids2table 2.3.1, so bagel-cli imports on 3.11 with the root lock. api and federation-api both ship a top-level package `app`; in one shared venv one shadows the other, so each package needs its own venv (`uv sync --package X`). The api/federation-api Dockerfiles build from the package uv.lock (Python 3.10 base image); the root lock does not cover 3.10, so images cannot switch to it without changing Dockerfiles and base images.
- Maintainer decisions (2026-11-09): per-package uv locks (no uv workspace during migration); own tagging job (no GitHub Releases). Following the plan's shared-matrix rule, the Python matrix is 3.12-3.13 with locked deps. Plan updated with Revised notes.
- migrate.sh commits the current migration/ directory as a generated commit before applying the patches (plan updated).

### Phase 3 work (2026-11-09)

Patch series (migration/patches/, authored in work/dev on top of the import + migration/ commit, exported with `git format-patch --zero-commit`; author/committer date = the import's fixed date, applied with `git am --committer-date-is-author-date`, so builds are deterministic). Plan step 9 numbering -> patch:
- 9.1 -> 0001 docs: root LICENSE (bagel-cli's, identical in all 5 packages) and README. migration/ docs come from the generated migration/ commit (plan revised).
- 9.2 -> 0002 build: hatch-vcs settings (root "../..", tag_regex, git_describe_command --match <prefix>-v*) in api, federation-api, bagel-cli.
- 9.3 dropped (no uv workspace, maintainer decision).
- 9.4 -> 0003 ci: root .pre-commit-config.yaml, .github/scripts/check-pr.sh + pr-checks.yml, check-unchanged.yml, .github/dependabot.yml, PR template.
- 9.5 -> 0004 ci: test-python.yml / test-node.yml (reusable), one workflow per package (path filters: package, deploy/, testdata/, .gitmodules, own + shared workflow), query-tool examples (+ comment), link-check, stale, scorecard, handle_external_pr.
- 9.6 -> 0005 ci: release-please config/manifest, release.yml (tag job, then release-please with skip-github-release), .github/scripts/tag-release.sh.
- 9.7 -> 0006 ci: docker-build.yml (reusable), docker-nightly.yml, docker-release.yml, bagel-cli-release.yml (PyPI then image), sites.yml (Netlify), images-validation.yml, .github/scripts/image-matrix.sh; packages/bagel-cli/Dockerfile.nightly: one `ARG SETUPTOOLS_SCM_PRETEND_VERSION` line (version as build argument; smaller than a root-context build; the ARG is not persisted in the image).
- 9.8 -> migration/ (generated commit): DEVELOPING.md, settings.sh, sync-to-old-repo.sh, check-unchanged.sh, allowed-changes.txt.
- 9.9 -> 0007 docs: "Working in the monorepo" section in each tool README.

Package edits (allowed-changes.txt, 14 paths): 5 symlinks, 3 pyproject.toml, bagel-cli Dockerfile.nightly, 5 README.md.

Implementation notes and findings:
- pre-commit: same hook revs as upstream, one entry per package with alias, files: scope and explicit config paths. federation-api's flake8 per-file-ignores path rewritten to the root-relative path (root config, not a package edit). api codespell gets --config=packages/api/.codespellrc (upstream read it from cwd). `pre-commit run --all-files` passes with no changes; pretty-format-json has no api files (same as upstream baseline).
- husky (`prepare` script) in a package subfolder leaves core.hooksPath unset (checked after npm ci in both frontends).
- release-please facts (source 17.11.2 / action v5.0.0): releasable = feat/feature, fix, perf, revert, or breaking; all other types (incl. deps) hidden. `simple` type writes only CHANGELOG.md (version.txt only if it exists).
- Squash merges: settings.sh sets squash commit message to BLANK, so conventional-commit lines of individual commits in a squash body cannot trigger releases.
- tag-release.sh pushes one tag per push (GitHub creates no push events when more than 3 tags are pushed at once).
- settings.sh uses `gh api` for variables (`gh variable` needs gh >= 2.31; this container has 2.23).
- sync-to-old-repo.sh: no rsync dependency; skips symlinks/submodules and strips the monorepo-only hatch-vcs block. Round trip packages/api -> fresh neurobagel/api clone: no diff.
- import.sh: clones now retry (a GitHub clone failed once with "early EOF").
- release-preview (migration/release-preview.mjs, release-please's own parser/versioning/changelog code on local history):
  - assembled history: bagel-cli 0.11.6 -> 0.12.0 (feat!, breaking -> minor), query-tool 0.17.1 -> 0.17.2 (fix #894), api / federation-api / annotation-tool: nothing to release.
  - synthetic multi-tool merge commit (feat(api) + fix(query-tool) commits, merge message with chore title): api 0.13.0 with only its entry, query-tool only its entry; the merge commit adds nothing. Same changes squashed as "chore:": nothing released.
  - cosmetic: changelog entries of imported commits render "neurobagel/<repo>#N" with the "#N" part linked to the monorepo's issue N. Affects only the first release PR's entries for imported commits; can be corrected by editing the release PR.
- The new README sections link to https://github.com/neurobagel/neurobagel, which 404s until the Phase 4 push; link checks (api linkspector, annotation-tool lychee) will pass only after the push.
- Gate run 1 (work/gate3, interrupted by a host sleep, continued): S8 found
  - api/federation-api listing diffs: only __pycache__/_version.py written into the verify clone by earlier checks (api/federation-api have no .dockerignore). verify.sh bug: S8 now builds from a pristine clone and cleans the upstream clones.
  - query-tool image build FAILS from the package folder: `tsc` includes cypress/, and UpdateExamples.cy.ts imports ../../neurobagel_examples/*.json through the symlink, which dangles in the build context. Fix (no package edit): docker-build.yml replaces the package's symlinks with copies of their targets before building (folded into patch 0006); verify S8 does the same. Plan risk note revised. To flag at Gate 3.
- Gate run 2 (work/gate3b): 116 PASS, 1 FAIL: annotation-tool Cypress component "Failed to fetch dynamically imported module ... component/support.ts" (known upstream flake, ~1/35; not fixed per plan). All 5 images now match upstream (0 listing differences). The same suite passed later in the run (README check: 185).
- Maintainer request: do not run the frontend suites twice. S5 now checks pytest only; vitest and Cypress counts are checked in S10 from the README commands (which run the full suites). Upstream image builds stay uncached (maintainer decision).
- The new S10 counts found a README bug that "block exits 0" missed: in query-tool's block, `npm run preview` also loads vite.config.ts, which requires NB_API_QUERY_URL, so the preview server never started; `cypress run --e2e` then gave up waiting for the server and still exited 0. Fixed by exporting NB_API_QUERY_URL once in the block (folded into patch 0007); block rerun alone: component 91, e2e 41.
- Gate run 3 (work/gate3c, `migration/migrate.sh work/gate3c`, from scratch, no manual edits, ~24 min): verify.sh "all checks passed", 117 PASS, 0 FAIL, 0 SKIP; 5 CI items listed for Phase 5. Highlights: history H1-H10 as in Phase 2; check-unchanged 14 allowed paths; pytest api 184 / federation-api 111 / bagel-cli 210 on 3.12 and 3.13; vitest 263; Cypress annotation-tool component 185, e2e 24, query-tool component 91, e2e 41; pre-commit on all files clean; versions from tags (next dev version; exact with a temporary tag); bagel wheel/sdist identical to upstream; 5 images identical to upstream; all guards fire (check-unchanged, check-dependabot, check-pr x7, tag-release x2); all README blocks run as written.
- Open plan decision resolved: bagel-cli nightly image gets its version as a build argument.

### Gate 3 review (2026-11-09)

Maintainer questions (open_questions.md) and decisions; patches 0001, 0003-0007 revised in work/dev and re-exported:
- GitHub Releases on: release-please creates the releases and the <component>-v<version> tags itself. tag-release.sh and the tag job are dropped (the version chain would otherwise depend on a second piece of code). Publishing runs from release-please's per-package outputs in release.yml (images, bagel-cli-release.yml, sites.yml as reusable workflows); docker-release.yml and all tag parsing are gone. sites.yml can still be run by hand for a released version.
- PR title check: amannn/action-semantic-pull-request; check-pr.sh dropped. The multi-tool merge policy is a review convention (PR template, DEVELOPING.md), helped by an informational release preview job (release-please dry run in the job summary), adopted from neurobagel/develop.
- Nightly images: dorny/paths-filter and one job per image; image-matrix.sh dropped. images-validation.yml lists its five builds explicitly.
- docker-build.yml: docker/metadata-action for image names, tags and OCI labels (as upstream). Found and fixed while rewriting: the calling jobs now grant `packages: write` (a reusable workflow cannot get more permissions than its caller; the ghcr pushes would have failed in Phase 5).
- No .github/scripts left. Remaining inline shell: ported upstream logic (query-tool examples, sites), symlink materialization, the bagel-cli nightly version, query-tool's package.json version, the registry-variable check.
- check-unchanged.yml and images-validation.yml are labelled TEMPORARY (removed with migration/, step 23).
- codespell for the frontends moved from test-node.yml into the root pre-commit config (each package's .codespellrc; the hooks repeat its skip globs as excludes, because codespell's skip globs do not match the root-relative paths pre-commit passes).
- Dependabot (from neurobagel/develop): python base image minor updates ignored (python:3.10 -> 3.13 counts as minor), Docker base images and submodule updates grouped.
- Docs: DEVELOPING.md moved to the repository root (patch 0001), root README "Working in this repository" section, package README links updated.
- neurobagel/develop comparison: adopted dependabot grouping/ignore, README structure, release preview; moved to Later (plan): one ci.yml with a changes job + aggregator, image builds on PRs + query-tool smoke test, bagel-cli wheel check on PRs, actionlint in CI, just/justfile, one codespell config; listed under "To consider" with context: root-context image builds, wheel-based bagel image, api integration tests in CI, per-tool Python matrices, tools/ naming, full-stack local env, pre-commit in GitHub Actions, bootstrap-sha CI check.
- verify-setup.sh: S2 now checks GitHub Releases on (no skip-github-release), release outputs for every package, the publishing jobs, no .github/scripts; S9 drops the check-pr/tag-release guards and adds the frontend codespell hook guard.
- Gate run 4 (work/gate3d): 110 PASS, 3 FAIL. (1, 2) The deletions of docker-release.yml and image-matrix.sh had not made it into patch 0006 (the `git rm` did not run); the new S2 checks caught both (actionlint on the stale docker-release.yml, `.github/scripts` not empty). Fixed in work/dev, patches re-exported. (3) query-tool Cypress e2e 40/41: Form.cy.ts "Selects different nodes in the nodes field", a MUI tooltip covers the option. Upstream flake: on an unchanged upstream clone Form.cy.ts failed 4 of 5 runs in this container (work/formflake.sh); README block reruns: 1 pass, 1 fail. Recorded under Known upstream issues; not fixed (no package edits).
- Gate run 5 (work/gate3e, from scratch, no manual edits): verify.sh "all checks passed", 113 PASS, 0 FAIL, 0 SKIP (fewer checks than run 3: the 9 check-pr/tag-release guards went with those scripts; added 4 S2 checks and 1 S9 codespell guard). query-tool e2e 41/41 this time.

## Mirror and timing proposal (2026-11-09, after Gate 3)

- Gate 3 passed (gate run 5); Phase 4 on hold. The maintainer added MIRROR_TO_OLD_REPOS.md: old repos must stay in sync (and their CI green) during a 3-4 month trial, and the migration may need rerunning later or late upstream changes brought in.
- Proposal written to ../proposal-mirror-and-timing.md (outside migration/, awaiting the maintainer's decision). Facts it rests on:
  - every old test workflow already triggers on push to main;
  - import trees equal old main except the deploy/testdata symlinks, whose upstream gitlinks pin exactly the imported data commits;
  - one hatch-vcs config (search_parent_directories, optional tag prefix, two --match) gives correct versions in both layouts (tested in scratch repos with hatchling + hatch-vcs).
- Decisions (2026-11-09):
  - Only the monorepo publishes.
  - Old repos get tags only, no GitHub Releases. Monorepo releases keep a tag plus a GitHub Release per tool.
  - Issues are outside the migration.
  - All tools switch over at once; staged switchover is a documented fallback.
  - Rehearsal in neurobagel/neurobagel-rehearsal.
  - No rehearsal copies of the old repos. The mirror opens PRs (branch monorepo-mirror) on the real old repos: draft and branch-only before switchover; after switchover it fast-forwards main once checks pass.
  - Folded into the plan (backup of the previous plan: work/plan-before-mirror.md).

## Mirror implementation (2026-11-09, Gate 3 rerun)

- Rehearsal repository: neurobagel/testplace (local clone testplace/, empty).
- Patch series (8 patches):
  - 0002: hatch-vcs settings that work in both repositories (search_parent_directories, optional tag prefix, --match <prefix>-v* and v*). Reworded.
  - 0003: check-unchanged.yml removed from CI (the script stays a local verify check). Reworded.
  - 0001: DEVELOPING.md: package .github/ etc. are live; the manual sync section is removed.
  - 0007: README sentence: the old repo is a read-only mirror.
  - New 0008: tools/mirror.py, mirror.yml, the mirror-check PR job, DEVELOPING "The old repositories" (mirror, trial rules, porting), README and PR template pointers.
- migration/:
  - switchover.sh (rulesets, disabled workflows, Dependabot security updates; --undo); old-repos-disabled.txt.
  - settings.sh --rehearsal (no branch protection) and MIRROR_OWNER.
  - migrate.sh writes bootstrap-sha from the import.
  - verify-mirror.sh (S11).
  - sync-to-old-repo.sh removed.
- S11 scope: Python pytest and annotation-tool vitest run in the mirrored old repos. The Cypress suites are not repeated there, because the frontend code is byte-identical to the monorepo, where S10 runs them.
- Development run (work/mir1, VERIFY_SKIP=tests,cypress,images,readme): all S11 checks pass. Its only "failures" were the 3 deliberate skips.
- Gate 3 rerun (work/gate3f, migrate.sh from scratch, no skips): 134 PASS, 2 FAIL, 0 SKIP. Every S11 check passes (old-repo pytest 184/111/210, vitest 263).
  - The 2 FAILs are S10 annotation-tool Cypress component (expected 185) and e2e (expected 24), both 0. The browser's CRI connection closed mid-run ("Target.getTargets will not run as the CRI connection ... has been closed") after the ColumnAnnotationCard spec, so Cypress stopped.
  - The README block still exited 0; the count check caught the crash.
  - Rerunning the same block alone in the same clone (work/gate3f-at-rerun.log): component 185/185, e2e 24/24, vitest 263.
  - annotation-tool code is unchanged in this series (only its README sentence changed). Listed for the maintainer as a deviation to accept; not fixed.

## Explicit merge switch (2026-11-10)

- Maintainer accepted the gate3f deviation (S10 annotation-tool Cypress browser crash; rerun green).
- Sanity check of the merge guard. Before, the mirror merged and tagged whenever an old repo's main had an "update" ruleset rule. Today none has one (checked via the API: the old repos have deletion, non_fast_forward, pull_request and required_status_checks rules), and none of the old mains has moved since the import (recipes, neurobagel_examples, api: 0 commits ahead). So an unrelated "restrict updates" rule would have made the mirror fast-forward a live repo.
- Maintainer decision: merging and tagging now also need the repository variable MIRROR_MERGE=true (mirror.py --allow-merge), set by hand after switchover. The ruleset check stays as a second condition.
- S11 gained a check: locked and green but without --allow-merge, nothing is written to main or tags.
- Maintainer decision (2026-11-10): S10 (README commands word for word, with the frontend vitest and Cypress counts) is no longer part of every gate run; it took about half the run time. It runs once, as a final check, in the switchover refresh (VERIFY_README=1). Without it, the frontend suites run in CI (checked in Phase 4) and annotation-tool vitest in S11. gate3g still ran it (already in progress).
- Reverted the same day: S10 is where the frontend suites (and api's integration tests against the test graph) run locally, and the README wrapper itself costs almost nothing. S10 stays in every gate run.
- Gate 3 rerun with the merge switch (work/gate3g, migrate.sh from scratch, no skips): verify: all checks passed. 137 PASS, 0 FAIL, 0 SKIP.
  - S10: annotation-tool vitest 263, Cypress component 185 and e2e 24; query-tool Cypress component 91 and e2e 41.
  - S11, new check: locked but MIRROR_MERGE unset leaves old main and tags untouched.
