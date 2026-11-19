<div align="center">

# `configure-nb`

[![Main branch checks status](https://img.shields.io/github/check-runs/neurobagel/configure-nb/main?style=flat-square&logo=github)](https://github.com/neurobagel/configure-nb/actions?query=branch:main)
[![Tests status](https://img.shields.io/github/actions/workflow/status/neurobagel/configure-nb/test.yaml?branch=main&style=flat-square&logo=github&label=tests)](https://github.com/neurobagel/configure-nb/actions/workflows/test.yaml)
[![Codecov](https://img.shields.io/codecov/c/github/neurobagel/configure-nb?token=Vn1do0lrCl&style=flat-square&logo=codecov&link=https%3A%2F%2Fcodecov.io%2Fgh%2Fneurobagel%2Fconfigure-nb)](https://app.codecov.io/gh/neurobagel/configure-nb)
[![Python versions static](https://img.shields.io/badge/python-3.10--3.14-blue?style=flat-square&logo=python)](https://www.python.org)
[![PyPI - Version](https://img.shields.io/pypi/v/configure-nb?style=flat-square&logo=pypi&link=https%3A%2F%2Fimg.shields.io%2Fpypi%2Fv%2Fconfigure-nb)](https://pypi.org/project/configure-nb/)
[![License](https://img.shields.io/github/license/neurobagel/configure-nb?style=flat-square&color=purple&link=LICENSE)](LICENSE)
[![OpenSSF Scorecard](https://img.shields.io/ossf-scorecard/github.com/neurobagel/configure-nb?style=flat-square&label=openssf%20scorecard)](https://scorecard.dev/viewer/?uri=github.com/neurobagel/configure-nb)

</div>

Configuration wizard for a Neurobagel deployment.

## Development environment

### Setting up a local development environment
1. Set up a Python environment. We [use `uv` for this](https://docs.astral.sh/uv/getting-started/installation/).

2. Clone the repository

    ```bash
    git clone https://github.com/neurobagel/configure-nb.git
    cd configure-nb
    ```

3. Install the CLI and all development dependencies in editable mode:

    ```bash
    uv sync --group dev

4. To run `configure-nb` during development, you can run it directly with `uv`:
    ```bash
    uv run configure-nb [OPTIONS]
    ```

Confirm that everything works by running the tests: 
`uv run pytest`

### Setting up code formatting and linting (recommended)

[pre-commit](https://pre-commit.com/) is configured in the development environment for this repository, 
and can be set up to automatically run a number of code linters and formatters on any commit you make 
according to the consistent code style set for this project.

Inside the repo, run the following to install the configured pre-commit "hooks":
```bash
uv run pre-commit install
```

pre-commit will now run automatically whenever you run `git commit`.
