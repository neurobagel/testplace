import logging

import pytest
from typer.testing import CliRunner

logger_name = "configure_nb.logger"


@pytest.fixture(scope="session")
def runner():
    return CliRunner()


@pytest.fixture()
def tmp_dotenv_path(tmp_path):
    """Temporary .env file path for testing output."""
    return tmp_path / ".env"


@pytest.fixture()
def tmp_federation_nodes_config_path(tmp_path):
    """Temporary local_nb_nodes.json path for testing output."""
    return tmp_path / "local_nb_nodes.json"


@pytest.fixture()
def tmp_ini_path(tmp_path):
    """Temporary INI file path for testing."""
    return tmp_path / "test_config.ini"


@pytest.fixture()
def propagate_warnings(caplog):
    """Only capture WARNING logs and above from the CLI."""
    caplog.set_level(logging.WARNING, logger=logger_name)


@pytest.fixture()
def propagate_info(caplog):
    """Only capture INFO logs and above from the CLI."""
    caplog.set_level(logging.INFO, logger=logger_name)


@pytest.fixture()
def propagate_errors(caplog):
    """Only capture ERROR logs and above from the CLI."""
    caplog.set_level(logging.ERROR, logger=logger_name)
