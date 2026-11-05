# Neurobagel

This repository holds the core Neurobagel tools. Each tool lives in its own folder under `packages/`, with its full history, and is versioned and released on its own.

| Tool | Folder | Published as |
|---|---|---|
| Node API (n-API) | [packages/api](packages/api) | Docker image `neurobagel/api` |
| Federation API (f-API) | [packages/federation-api](packages/federation-api) | Docker image `neurobagel/federation_api` |
| Annotation tool | [packages/annotation-tool](packages/annotation-tool) | https://annotate.neurobagel.org |
| CLI (`bagel`) | [packages/bagel-cli](packages/bagel-cli) | PyPI `bagel`, Docker image `neurobagel/bagelcli` |
| Query tool | [packages/query-tool](packages/query-tool) | Docker image `neurobagel/query_tool`, https://query.neurobagel.org |

Shared folders:

- [deploy/](deploy): the Docker Compose recipes for deploying Neurobagel (formerly `neurobagel/recipes`).
- [testdata/](testdata): example data and API responses used by the tools' tests (formerly `neurobagel/neurobagel_examples`).

The user documentation is at https://neurobagel.org.

## Working in this repository

Clone with submodules (bagel-cli's data folders are submodules) and install the commit hooks once:

```bash
git clone --recurse-submodules https://github.com/neurobagel/neurobagel.git
cd neurobagel
uv tool install pre-commit   # or: pipx install pre-commit
pre-commit install           # pre-commit checks on every commit; post-merge runs npm ci in a frontend whose package.json changed
```

- **One tool at a time.** Each tool keeps its own environment (`uv.lock` or `package-lock.json`) and commands: work from its folder, `packages/<tool>/`, and follow the "Working in the monorepo" section of its README.
- **Pull request titles are conventional commits** (`fix(api): ...`, `feat(query-tool): ...`, `chore: ...`). PRs are squash-merged with the title as the commit message, and the title decides the release. A PR that should release more than one tool needs one commit per tool and a merge commit.
- **Releases** are made by release-please from one combined release PR; each tool has its own version, changelog and tags `<tool>-v<version>`.
- **The old repositories** (neurobagel/api, ...) are read-only mirrors of their folders here while the monorepo is on trial; keep each package self-contained.

Details (CI, releases, publishing targets, dependency updates, the mirror and the trial rules, repository settings) are in [DEVELOPING.md](DEVELOPING.md).

## License

[MIT](LICENSE)
