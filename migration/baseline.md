# Upstream baseline (Phase 1)

Run 2026-11-09 on fresh clones of upstream `main` (commits in inventory.md), in the migration container. Scripts and full logs: `monorepo-migration/baseline/` (run-py.sh, run-js.sh, run-cypress.sh, logs/).

## Python (pytest)

Each run: `UV_PROJECT_ENVIRONMENT=.venv-<py>-<mode> uv sync --python <py> --group dev [--upgrade]`, then `uv run --no-sync --python <py> pytest [args]`.

| tool | Python | deps | pytest args | result |
|---|---|---|---|---|
| api | 3.10, 3.11, 3.12, 3.13 | locked | (default: `-m "not integration"` from pytest.ini) | 184 passed, 6 deselected (each version) |
| api | 3.10, 3.11, 3.12, 3.13 | locked | `-m "integration or not integration"`, test graph up (`docker compose up -d test_graph export_datasets_metadata`) | 190 passed (each version) |
| federation-api | 3.10, 3.11, 3.12, 3.13 | locked | (none) | 111 passed (each version) |
| bagel-cli | 3.11 | locked | `-m "integration or not integration"` | **collection error** (exit 4): `NameError: name 'Session' is not defined` |
| bagel-cli | 3.12, 3.13, 3.14 | locked | same | 210 passed (each version) |
| bagel-cli | 3.11, 3.12, 3.13, 3.14 | `--upgrade` (as upstream CI) | same | 210 passed, 20 warnings (each version) |

bagel-cli on 3.11: the lock pins bids2table 2.1.2; on 3.11 its import pulls in cloudpathlib's S3 client, which instantiates a boto3 `Session` that is not installed. `--upgrade` resolves bids2table 2.3.1, which does not. On 3.12+ cloudpathlib is not installed. Whether the monorepo's root uv.lock has this problem depends on how it resolves bids2table (Phase 3).

Warnings (pre-existing, informational): pandas FutureWarning in api `utility.py:410`; Starlette `httpx` deprecation in api and f-API conftest; pandera Pandas4Warning with upgraded deps in bagel-cli.

### Service-dependent tests (skip in monorepo CI)

Need a running graph store (api `integration` marker; upstream CI starts it from the recipes + neurobagel_examples submodules):

- api tests/test_datasets.py::test_compact_uri_query_succeeds
- api tests/test_subjects.py::test_app_with_invalid_environment_vars
- api tests/test_subjects.py::test_integration_query_without_auth_succeeds
- api tests/test_subjects.py::test_only_imaging_and_phenotypic_sessions_returned_in_query_response
- api tests/test_subjects.py::test_min_cell_size_removes_results
- api tests/test_subjects.py::test_and_query_returns_correct_matching_subjects

These are selected by the existing marker; skipping them in CI = running pytest with its default `-m "not integration"` (api) instead of upstream CI's `-m "integration or not integration"`. Expected monorepo count: api 184.

### Internet-dependent tests (not service-dependent; proposed: keep running)

With networking disabled (`unshare -rn`), these also fail. They fetch public files (communities configs, vocabularies, pipeline catalog, etc. from GitHub) and pass in upstream CI. They need no service that we run.

- api (7): test_app_events.py::{test_fetched_configs_includes_neurobagel, test_app_exits_when_config_unrecognized, test_app_exits_when_datasets_metadata_file_not_found, test_neurobagel_vocabularies_fetched_successfully, test_neurobagel_namespaces_fetched_successfully}; test_security.py::{test_missing_client_id_raises_error_when_auth_enabled, test_missing_client_id_ignored_when_auth_disabled}
- federation-api (1): test_security.py::test_missing_client_id_ignored_when_auth_disabled
- bagel-cli (11): integration/test_cli_bids.py (3), integration/test_cli_derivatives.py (3), integration/test_cli_pheno.py (4), unit/test_logging.py::test_verbosity_level[1-...] (1)

## Python lint (pre-commit, each repo's own config)

`pre-commit run --all-files` in each clone: api, federation-api, bagel-cli all pass, no files modified.

## Frontends

| tool | check | command | result |
|---|---|---|---|
| annotation-tool | install | `npm ci` | ok |
| annotation-tool | typecheck | `npm run typecheck` | pass |
| annotation-tool | lint | `npm run lint:check` | pass |
| annotation-tool | format | `npm run format:check` | pass |
| annotation-tool | codespell | `codespell` (clean checkout, .codespellrc) | pass |
| annotation-tool | links | lychee `**/*.md **/*.html **/*.ts **/*.tsx` (lychee.toml) | pass: 461 total, 400 OK, 61 excluded, 0 errors |
| annotation-tool | unit | `npm run test:unit` (vitest) | 30 files, 263 tests passed |
| annotation-tool | build | `npm run build` | ok |
| annotation-tool | e2e | `.env` NB_DISABLE_CONFIG=false; build; preview :5173; `cypress run --e2e` | 17 specs, 24 tests passed |
| annotation-tool | component | build; `cypress run --component` | 37 specs, 185 tests passed |
| query-tool | install | `npm ci` | ok |
| query-tool | typecheck | `npm run typecheck` | pass (not run in upstream CI except via `npm run build`) |
| query-tool | lint | `npm run lint:check` | pass |
| query-tool | format | `npm run format:check` | pass |
| query-tool | codespell | `codespell` (clean checkout) | pass |
| query-tool | build | `npm run build` | needs `.env` (NB_API_QUERY_URL), as CI writes it; ok with it |
| query-tool | component | `.env` NB_API_QUERY_URL=https://federate.neurobagel.org/; build; `cypress run --component` | 18 specs, 91 tests passed |
| query-tool | e2e | `.env` + NB_ENABLE_AUTH=true, NB_QUERY_CLIENT_ID=mockclientid; build; preview; `cypress run --e2e` | 9 specs, 41 tests passed (includes UpdateExamples.cy.ts) |

Cypress ran in `docker.io/cypress/included:15.21.1` (matches the locked cypress 15.21.1), host network. All e2e specs use `cy.intercept` for API calls (query-tool Feedback.cy.ts has none and makes no API call); no service-dependent frontend tests. annotation-tool component flake (~1/35) did not occur in this run.

Running codespell inside a working tree with node_modules reports typos in node_modules; upstream CI runs it before `npm ci`. The monorepo hook/CI must not scan node_modules.

## Link checks (api)

linkspector (`.linkspector.yml`, README.md), run in the cypress image as a non-root user after `npx puppeteer@^24 browsers install chrome` (as upstream's workaround): 1 failure, the known SNOMED link `http://purl.bioontology.org/ontology/SNOMEDCT/248152002` (403). Upstream's last linkspector run (2026-11-05) passed, so this link fails intermittently or depends on the client network.

## Known upstream issues confirmed

- bagel-cli fails at import on 3.11 with its locked deps (above).
- api SNOMED link (above).
- query-tool build needs NB_API_QUERY_URL (consistent with the known entrypoint issue).
- Not exercised: query-tool compose test profile (known broken), recipes networking issue.
