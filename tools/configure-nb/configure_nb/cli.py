from pathlib import Path
from typing import Annotated

import pydantic
import typer

from . import utility as util
from .federation_nodes_model import (
    FEDERATION_NODE_SECTION_PREFIX,
    InternalFederationNode,
    InternalFederationNodes,
)
from .logger import VerbosityLevel, configure_logger, log_error, logger
from .models import COMPOSE_PROFILE_TO_CLASS_MAP, Quickstart

NB_PUBLIC_NODE_DIRECTORY = "https://github.com/neurobagel/menu/blob/main/node_directory/neurobagel_public_nodes.json"

configure_nb = typer.Typer(
    context_settings={"help_option_names": ["-h", "--help"]},
)


@configure_nb.command()
def main(
    config_file: Annotated[
        Path,
        typer.Option(
            "--config-file",
            "-c",
            help="Path to a configuration file (.ini).",
            exists=False,
            file_okay=True,
            dir_okay=False,
            resolve_path=True,
        ),
    ] = Path("nb_config.ini"),
    output_dir: Annotated[
        Path,
        typer.Option(
            "--output-dir",
            "-o",
            help="Path to the directory where generated configuration files should be saved.",
            file_okay=False,
            dir_okay=True,
            exists=True,
            resolve_path=True,
        ),
    ] = Path("."),
    verbosity: Annotated[
        VerbosityLevel,
        typer.Option(
            "--verbosity",
            "-v",
            callback=configure_logger,
            help="Set the logging verbosity level. 0 = show errors only; 1 = show errors, warnings, and informational messages; 2 = show all logs, including debug messages.",
        ),
    ] = VerbosityLevel.INFO,
    # TODO: Add option to explicitly allow overwriting?
):
    """
    Generate valid configuration files for Neurobagel deployment configuration.
    Always creates a .env file; additionally creates a local_nb_nodes.json file for a test or portal deployment.
    """
    out_dotenv_path = output_dir / ".env"

    # Load configuration from INI file
    if config_file.exists():
        logger.info(f"Loading configuration from file: {config_file}")
        ini_contents = util.load_ini_as_dict(config_file)
    else:
        logger.info(
            "No configuration file provided. Using default values for all settings."
        )
        ini_contents = {}

    # Determine and validate deployment profile
    compose_profile = ini_contents.get("compose", {}).get("COMPOSE_PROFILES")
    config_class = util.get_config_class_for_compose_profile(compose_profile)
    if config_class is None:
        log_error(
            logger,
            f"Invalid COMPOSE_PROFILES value: {compose_profile!r}. "
            f"Expected one of {list(COMPOSE_PROFILE_TO_CLASS_MAP.keys())}.",
        )
    elif config_class is Quickstart:
        logger.info(
            "The COMPOSE_PROFILES variable was not set. Defaulting to a test deployment configuration."
        )
    else:
        logger.info(f"Deployment configuration: {compose_profile}")

    # Extract sections related to environment variables vs federation node definitions (if any)
    # NOTE: We skip this for the "node" profile so that the config class validation can detect any sections
    # related to federation node definition as unrecognized for that profile
    if compose_profile == "node":
        deployment_config_vars = ini_contents.copy()
        in_federation_nodes: dict[str, dict] = {}
    else:
        deployment_config_vars, in_federation_nodes = (
            util.split_federation_node_sections_from_env_vars(ini_contents)
        )

    # Validate deployment configuration variables
    try:
        config = config_class.model_validate(deployment_config_vars)
    except pydantic.ValidationError as err:
        if config_file.exists():
            # TODO: Can customize validation error from Pydantic to be more user friendly
            err_message = f"There are problems with configuration values in {config_file.name}. Please check your configuration."
        else:
            err_message = (
                "Failed to apply default configuration values. "
                "This is unexpected - please report the issue at https://github.com/neurobagel/configure-nb/issues."
            )
        log_error(logger, f"{err_message}\nValidation details:\n {err}")

    if compose_profile != "node":
        out_nodes_json_path = output_dir / "local_nb_nodes.json"

        # Validate internal federation nodes
        if compose_profile == "portal" and not in_federation_nodes:
            logger.warning(
                "No internal nodes were defined for query federation in the configuration INI file. "
                f"Federation will be limited to nodes in the Neurobagel public node directory ({NB_PUBLIC_NODE_DIRECTORY}). "
                "To define an internal node to include in query federation, "
                f"use an INI section header in the form \\[{FEDERATION_NODE_SECTION_PREFIX}<id>].",
            )
        if in_federation_nodes:
            node_validation_errs = util.validate_federation_node_definitions(
                in_federation_nodes
            )
            if node_validation_errs:
                log_error(
                    logger,
                    f"The configuration contains {len(node_validation_errs)} invalid definition(s) of internal federation nodes:\n"
                    + "\n\n".join(node_validation_errs),
                )

        # Collect internal federation nodes for output
        out_federation_nodes = []
        if compose_profile is None and not in_federation_nodes:
            out_federation_nodes.append(
                InternalFederationNode(
                    # TODO: Should we rename this to "Default local graph" or similar to convey that it is a default?
                    name="Local graph 1",
                    api_url="http://api:8000",
                )
            )
        else:
            for node_definition in in_federation_nodes.values():
                out_federation_nodes.append(
                    InternalFederationNode.model_validate(node_definition)
                )
        logger.info(
            f"{len(out_federation_nodes)} internal federation node(s) will be included for federation."
        )

        out_federation_nodes = InternalFederationNodes(
            out_federation_nodes
        ).model_dump(by_alias=True, mode="json")
        util.write_json(out_nodes_json_path, out_federation_nodes)
        logger.info(
            f"Internal federation nodes configuration successfully written to: {out_nodes_json_path}"
        )

    util.write_text_file(out_dotenv_path, util.config_to_env_str(config))
    logger.info(
        f"Environment variable configuration successfully written to: {out_dotenv_path}"
    )
