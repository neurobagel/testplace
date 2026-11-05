# Upstream inventory (Phase 1)

Snapshot of upstream `main` on 2026-11-09 (fresh clones):

| repo | HEAD | last tag |
|---|---|---|
| api | 3292b9e | v0.12.0 |
| federation-api | d17a4e6 | v0.10.0 |
| annotation-tool | d15bb9d | v0.7.10 |
| bagel-cli | 5c51333 | v0.11.6 |
| query-tool | f5020c7 | v0.17.1 |
| recipes | e72cdb7 | v0.9.2 |
| neurobagel_examples | 00bf8ee | (none) |

Decision values:
- **port**: recreated at the monorepo root (root `.github/`, root pre-commit, repo settings). The package copy stays as dead code.
- **drop**: not carried over. The package copy stays as dead code.
- **keep**: stays where it is today (old repo, org setting or external service), untouched.

Items marked **?** need a maintainer decision (listed at the end).

## Shared org template items

These are byte-identical across the tool repos (from neurobagel/workflows templates). Per-repo tables refer to them by name.

| item | what it does | decision | note |
|---|---|---|---|
| add_iss2project.yml | adds new issues to org project 1 (bot app token) | drop | no longer needed |
| handle_external_pr.yml | labels fork PRs `_community`, pre-commit.ci PRs `_bot` | port | one root copy |
| stale.yml | marks issues stale after 75 days | port | one root copy |
| scorecard.yml | OSSF Scorecard on push to main + weekly | port | one root copy |
| release.yaml + .autorc | `auto shipit`: label-driven version bump, CHANGELOG.md commit, git tag, GitHub Release | drop | replaced by release-please (conventional commits instead of pr-* labels) |
| build_docker_nightly.yml | `:nightly` image on every push to main, Docker Hub, amd64+arm64 | port | changed packages only; registry/namespace from variables |
| build_docker_on_release.yml | `vX.Y.Z` + `latest` on GitHub Release, amd64+arm64 | port | triggered per released component instead of GitHub Release |
| dependabot.yml | github-actions, gitsubmodule, npm (no majors, grouped), uv (security only); labels `_bot`, `dependencies` | port | one root file with directories and groups |
| pull_request_template.md | PR checklist with `[ENH]`/`[FIX]` title prefixes and release labels | port | root template rewritten for conventional commits |
| CodeQL default setup | repo setting (runs show as "Push on main", "Scheduled", "PR #N") | port | enable on the new repo (setting) |
| Dependabot security updates | repo setting | port | enable on the new repo (setting) |
| Codecov | coverage upload in test workflows; codecov/project and codecov/patch statuses on main | port ! | upload per package with a flag; needs CODECOV_TOKEN for the new repo |

## api

| item | type | decision | note |
|---|---|---|---|
| test.yaml | CI: pytest on 3.10-3.13, starts test graph via `docker compose up -d test_graph export_datasets_metadata` (uses recipes + neurobagel_examples submodules), runs `-m "integration or not integration"`, Codecov | port | non-integration tests run on the shared matrix; `integration` tests (6, need graph store) are service-dependent and skipped |
| linkspector.yml | CI: link check of README.md (`.linkspector.yml`) on push/PR | port | scoped to packages/api/README.md; known failing SNOMED link - my note: ideally move to repo root as central workflow |
| cff_validation.yml | CI: cffconvert --validate | drop | per plan; CITATION.cff stays as dead code |
| build_docker_nightly / on_release | Docker Hub `neurobagel/api` | port | context = package folder; Dockerfile uses package `pyproject.toml` + `uv.lock` (see Phase 3 note) |
| pre-commit (pre-commit.ci) | black, flake8 (.flake8), check-yaml, check-toml, pretty-format-json --autofix, isort (--settings-path), codespell (--toml), docker-compose-check (skipped on pre-commit.ci), mypy (+pydantic) | port | root pre-commit hooks scoped to packages/api; pre-commit.ci runs on the monorepo (Gate 1) |
| auto release / .autorc | tags vX.Y.Z, GitHub Release, CHANGELOG.md | drop | release-please |
| submodules recipes, neurobagel_examples | test graph + test data | port | symlinks to deploy/ and testdata/ |
| deploy target | Docker Hub neurobagel/api (`nightly`, `vX.Y.Z`, `latest`) | port | |
| documented test cmd | `uv sync --group dev`; `uv run pytest` (default `-m "not integration"` in pytest.ini); integration: `docker compose up -d test_graph` then `uv run pytest -m "integration or not integration"` | port | |

## federation-api

| item | type | decision | note |
|---|---|---|---|
| test.yaml | CI: pytest on 3.10-3.13, Codecov, + workflow_dispatch | port | no service-dependent tests expected (confirm in baseline) |
| build_docker_nightly / on_release | Docker Hub `neurobagel/federation_api` | port | same uv.lock note as api |
| pre-commit (pre-commit.ci) | black, flake8 (inline args: --extend-ignore=E501 --extend-select=B950 --per-file-ignores=./app/api/models.py:F722), check-yaml, isort (no args), codespell (no args), check-github-workflows | port ! | flake8 per-file-ignores path is relative to cwd (`./app/...`): must be rewritten or run from the package folder; isort/codespell have no config args, so their configs must be passed explicitly (plan rule) |
| auto release | | drop | release-please |
| deploy target | Docker Hub neurobagel/federation_api | port | |
| documented test cmd | `uv sync --group dev`; `uv run pytest` | port | |

## annotation-tool

| item | type | decision | note |
|---|---|---|---|
| checks.yaml: tsc, eslint, prettier | CI | port | `npm run typecheck`, `lint:check`, `format:check` in packages/annotation-tool |
| checks.yaml: codespell | CI (.codespellrc) | port | |
| checks.yaml: lychee link check | CI: `**/*.md **/*.html **/*.ts **/*.tsx`, lychee.toml | port | scoped to the package |
| tests.yaml: e2e | Cypress e2e against `npm run preview`, `.env` NB_DISABLE_CONFIG=false | port | |
| tests.yaml: component | Cypress component | port | known flake ~1/35 (Vite optimizeDeps) |
| tests.yaml: unit | vitest `npm run test:unit` | port | |
| tests.yaml: merge-coverage | nyc merge of e2e+component+unit, Codecov with fail_ci_if_error | port **?** | tied to the Codecov decision |
| deploy.yaml: GitHub Pages | on GitHub Release: build with NB_ANALYTICS=true, deploy to Pages (annotate.neurobagel.org, CNAME set in repo Pages settings) | port  | build for netlify, same as current beta-annotate, see question |
| deploy.yaml: Netlify | on GitHub Release: build with NB_GOOGLE_APPS_SCRIPT_URL, `netlify deploy --prod` (NETLIFY_PROD_SITE_ID, NETLIFY_AUTH_TOKEN) | port | |
| build_docker_on_release.yml | template workflow, but there is no Dockerfile; last run (2026-11-02) failed | drop | no image is published today |
| husky pre-commit | `npx lint-staged`: typecheck + lint on ts/tsx, format:check on all staged | port | as root pre-commit hooks scoped to the package |
| husky post-merge | `npm ci` when package.json changed | port | pre-commit post-merge hook (per plan) |
| `"prepare": "husky install"` | runs on `npm ci` | keep | must be harmless in a subfolder (verify in Phase 3: husky must not take over core.hooksPath) |
| auto release (npm plugin, no publish: package is private) | bumps package.json version, tags, GitHub Release | drop | release-please node type bumps package.json |
| deploy target | GitHub Pages annotate.neurobagel.org; Netlify prod site | port | |
| documented test cmd | `npm ci`; `npm run test:unit`; `npx cypress run --component`; `npx cypress run --e2e` (needs preview server) | port | |

## bagel-cli

| item | type | decision | note |
|---|---|---|---|
| test.yml | CI on every push/PR: 3.11-3.14, `uv sync --group dev --upgrade` (ignores lockfile), `pytest -m "integration or not integration"`, Codecov | port | shared matrix 3.11-3.13 with locked deps; 3.14 not in the intersection |
| cff_validation.yml | CI | drop | per plan |
| build_docker_nightly.yml | builds `Dockerfile.nightly` from source (`COPY . /app`, needs .git for hatch-vcs), fetch-depth 0, submodules recursive | port | needs the version from monorepo tags (open decision) |
| build_docker_on_release.yml | `Dockerfile` does `pip install bagel` from PyPI | port | must run after the PyPI upload of the same release |
| release.yaml (auto + exec plugin) | after release: `python -m build && twine upload dist/*` with PYPI_TOKEN | port | PyPI release of bagel per released component |
| pre-commit (pre-commit.ci) | black, flake8 (.flake8), check-yaml, check-toml, isort (args), codespell, mypy | port ! | codespell has no config arg here; pass config explicitly |
| submodules communities, pipeline-catalog, bids-examples | packaged data / test data | keep | stay submodules (root .gitmodules) |
| submodule tests/neurobagel_examples | test data | port | symlink to testdata/ |
| deploy target | PyPI `bagel`; Docker Hub `neurobagel/bagelcli` (`nightly`, `vX.Y.Z`, `latest`) | port | plan's artifact list omits neurobagel/bagelcli; it exists and must keep its name |
| documented test cmd | `uv sync --group dev`; `git submodule update --init`; `uv run pytest .` | port | |

## query-tool

| item | type | decision | note |
|---|---|---|---|
| lint.yaml | `npm run lint:check` | port | |
| prettier.yaml | `npm install --save-dev prettier && npx prettier --check .` | port | as `npm run format:check` (same check, without mutating package.json) |
| codespell.yml | codespell (.codespellrc) | port | |
| component-test.yaml | Cypress component, `.env` NB_API_QUERY_URL | port | |
| e2e-test.yaml | Cypress e2e vs preview, `.env` with NB_ENABLE_AUTH=true | port | tests intercept the API (mocked); not service-dependent (confirm in baseline) |
| generate_examples_diff.yaml + comment_examples_diff.yaml | on PR: run UpdateExamples.cy.ts, diff TSVs against neurobagel_examples@main, sticky comment via bot | port **?** | compare against testdata/ instead |
| updated_examples.yaml | on push to main: regenerate TSVs, open PR on neurobagel/neurobagel_examples | port  | testdata/ is now the only copy: PR would target the monorepo |
| deploy.yaml (GitHub Pages) | on GitHub Release: inject analytics scripts into index.html, set package.json version from release tag (or `releases/latest` API), build, deploy (query.neurobagel.org) | port  | build for netlify, but keep injecting the plausible script |
| build_docker_nightly.yml | sets package.json version `build:<sha>`, amd64 only | port | |
| build_docker_on_release.yml | sets package.json version from release tag, builds, then commits the bump back to main with bot | port | drop the commit-back step (release-please bumps package.json) |
| husky pre-commit / post-merge | same as annotation-tool | port | |
| `"prepare": "husky"` | | keep | same check as annotation-tool |
| auto release (npm plugin, private) | | drop | release-please |
| submodules recipes, neurobagel_examples | compose test profile (broken upstream), UpdateExamples spec | port | symlinks to deploy/, testdata/ |
| deploy target | Docker Hub `neurobagel/query_tool`; GitHub Pages query.neurobagel.org | port | |
| documented test cmd | `npm ci`; `npx cypress open` (interactive); CI uses `cypress run --component` / `--e2e` | port | |

## recipes (copied to deploy/)

| item | type | decision | note |
|---|---|---|---|
| auto release (tags v0.9.2, GitHub Releases) | users are pointed at recipes releases by the docs | drop | we will have to create an efferent copy of this directory and push to the old recipes repo for now |
| compatibility.yaml | twice daily: compose up with `latest` and `nightly` published images, Cypress, Slack on failure | drop | keep the test but don't run it / don't wire up to CI |
| test_setup.yml, test_fullstack_e2e.yml, actions/test-setup | full-stack 2-node setup + Cypress | drop | keep the test but don't run it. This will have to get done properly later.  |
| shared template items | | as above | |

## neurobagel_examples (copied to testdata/)

| item | type | decision | note |
|---|---|---|---|
| make_api_responses.yml | manual: spins up 2 nodes from recipes, regenerates api-responses/*.json, PR to itself | drop | keep tests, don't run. list under "next" so we do this properly  |
| shared template items | | as above | |

## Secrets and variables used

Secrets: DOCKERHUB_USERNAME, DOCKERHUB_TOKEN, CODECOV_TOKEN, NB_BOT_KEY, PYPI_TOKEN, NETLIFY_PROD_SITE_ID, NETLIFY_AUTH_TOKEN, NB_GOOGLE_APPS_SCRIPT_URL, NB_SLACK_WEBHOOK (recipes). Variables: NB_BOT_ID, DOCKERHUB_REPO (per repo). The PAT cannot list org/repo secrets (403), so where each is defined (org vs repo) must be confirmed by the maintainer.

## Notes for later phases (not decisions)

- api and federation-api Dockerfiles build from the package's own `pyproject.toml` + `uv.lock` (`uv export --frozen`). With a root uv workspace, the root `uv.lock` is what tests and dependabot use, so the package `uv.lock` (which the images use) would stop being updated. Must be resolved in Phase 3.
- api and federation-api images use `python:3.10`, which is outside the 3.11-3.13 test matrix.
- query-tool's Dockerfile copies the whole package folder into the build stage (`COPY . .`), including the recipes/neurobagel_examples symlinks; they do not resolve inside the build context. The final stage contains only `dist/`.
- Upstream releases currently create GitHub Releases, and deploys/images trigger on `release: published`. Without GitHub Releases, all publish workflows must trigger on component tags / release-please outputs.
