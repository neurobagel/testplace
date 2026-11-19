import logging
import sys
from enum import Enum
from typing import NoReturn

import typer
from rich.logging import RichHandler

LOG_FMT = "%(message)s"
DATETIME_FMT = "[%Y-%m-%d %X]"

# Check if code is currently running in a test environment
IS_TESTING = "pytest" in sys.modules

logger = logging.getLogger("configure_nb.logger")


class VerbosityLevel(str, Enum):
    """Enum for verbosity levels."""

    ERROR = "0"
    INFO = "1"
    DEBUG = "2"


verbosity_log_levels = {
    VerbosityLevel.ERROR: logging.ERROR,
    VerbosityLevel.INFO: logging.INFO,
    VerbosityLevel.DEBUG: logging.DEBUG,
}


def configure_logger(verbosity: VerbosityLevel = VerbosityLevel.INFO) -> None:
    """Configure a logger with the specified logging level."""
    level = verbosity_log_levels[verbosity]

    # Reset handlers to avoid duplicate log messages
    logger.handlers.clear()

    handler = RichHandler(show_path=False, rich_tracebacks=True, markup=True)
    formatter = logging.Formatter(fmt=LOG_FMT, datefmt=DATETIME_FMT)
    handler.setFormatter(formatter)
    logger.addHandler(handler)

    logger.setLevel(level)

    # propagate should be False to avoid duplicate messages from root logger
    # except when testing because otherwise Pytest does not capture the logs
    if not IS_TESTING:
        logger.propagate = False


def log_error(logger: logging.Logger, message: str) -> NoReturn:
    """Log an exception with an informative error message, and exit the app."""
    logger.error(message)
    raise typer.Exit(code=1)
