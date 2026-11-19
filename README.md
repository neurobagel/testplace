# Neurobagel

This repository holds Neurobagel tools and the deployment recipes. Each one lives in its own folder, with its full history, and is versioned and released on its own.

| Folder | What | Published as |
|---|---|---|
| [tools/api](tools/api) | Node API (n-API) | Docker image `neurobagel/api` |
| [tools/federation-api](tools/federation-api) | Federation API (f-API) | Docker image `neurobagel/federation_api` |
| [tools/query-tool](tools/query-tool) | Query tool | Docker image `neurobagel/query_tool`, https://query.neurobagel.org |
| [tools/configure-nb](tools/configure-nb) | Configuration CLI (`configure-nb`) | PyPI `configure-nb` |
| [recipes](recipes) | Docker Compose recipes for deploying Neurobagel | GitHub Releases (tags `recipes-v<version>`) |
| [examples](examples) | Example data and API responses used by the tools' tests | not released |

The annotation tool and the CLI (`bagel`) are developed in their own repositories for now ([neurobagel/annotation-tool](https://github.com/neurobagel/annotation-tool), [neurobagel/bagel-cli](https://github.com/neurobagel/bagel-cli)).

The user documentation is at https://neurobagel.org.

## Working in this repository

Clone and install the commit hooks once:

```bash
git clone https://github.com/neurobagel/neurobagel.git
cd neurobagel
uv tool install pre-commit   # or: pipx install pre-commit
pre-commit install           # every tool's own hooks plus the repository-wide ones
```

- **One tool at a time.** Each tool keeps its own environment (`uv.lock` or `package-lock.json`), configs and commands: work from its folder (see "Local development environment" in DEVELOPING.md and the "Working in the monorepo" section of the tool's README).
- **Pull request titles are conventional commits** (`fix(api): ...`, `feat(query-tool): ...`, `docs: ...`). PRs are squash-merged with the title as the commit message, and the title decides the release. A PR that should release more than one tool needs one commit per tool and a merge commit.
- **Releases** are made by release-please from one combined release PR; each tool and recipes has its own version, changelog and tags `<name>-v<version>`.

Details (CI, releases, publishing targets, dependency updates, shared configs, repository settings) are in [DEVELOPING.md](DEVELOPING.md).

## License

[MIT](LICENSE)
