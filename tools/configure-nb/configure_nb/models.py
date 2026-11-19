from typing import Annotated, ClassVar, Literal

from pydantic import (
    AfterValidator,
    BaseModel,
    ConfigDict,
    Field,
    model_validator,
)
from typing_extensions import Self

from .logger import logger

# INI section names corresponding to each service
SERVICE_INI_SECTIONS = {
    "node-api": "service:node-api",
    "graph": "service:graph",
    "federation-api": "service:federation-api",
    "query": "service:query",
    "experimental": "service:experimental",
    "compose": "compose",
}


def path_has_leading_slash(path: str) -> str:
    """Raise an error if the provided path does not start with a leading slash."""
    # TODO: Should we prepend the leading slash automatically?
    if path and not path.startswith("/"):
        raise ValueError("Base path must start with a leading slash.")
    return path


def domain_has_no_url_scheme(domain: str) -> str:
    """Raise an error if the provided domain includes a URL scheme."""
    if domain.startswith(("http://", "https://")):
        raise ValueError(
            "Domain name must not include a URL scheme (http:// or https://)."
        )
    return domain


def add_prefix_to_database_name(name: str) -> str:
    """If the provided database name does not start with the expected prefix, add it."""
    expected_prefix = "repositories/"
    if not name.startswith(expected_prefix):
        return expected_prefix + name
    return name


def filesystem_path_is_explicit(path: str) -> str:
    """Raise an error if the provided value for a path variable is not an explicit path."""
    if not path.startswith(("./", "../", "/")):
        raise ValueError(
            "Path must be an explicit path and start with './', '../', or '/' to ensure it is correctly interpreted as a local directory by Docker Compose. "
            "Example: use './data' instead of 'data'."
        )
    return path


def _get_extra_fields(cls: type[BaseModel], data: dict) -> set[str]:
    """Return fields that are present in the input data but are not defined in the Pydantic model."""
    recognized_fields = {
        field.alias or name for name, field in cls.model_fields.items()
    }
    return set(data) - recognized_fields


class BaseService(BaseModel):
    """
    Base model for the configuration of a specific Neurobagel service,
    with custom warning logic about variables that are not recognized by the INI section corresponding to the service.
    """

    # Define a class variable for the INI section name so it can be used for logging
    # without it ending up in the model fields
    ini_section: ClassVar[str]

    model_config = ConfigDict(extra="ignore")

    @model_validator(mode="before")
    @classmethod
    def warn_extra_fields(cls, data):
        if isinstance(data, dict):
            if extra_fields := _get_extra_fields(cls, data):
                logger.warning(
                    f"Section \\[{cls.ini_section}] contains variables that are not recognized or used by the service:\n"
                    + "\n".join(
                        f" - {extra_field}" for extra_field in extra_fields
                    )
                    + "\nThese variables will be ignored."
                )
        return data


class Graph(BaseService):
    """Model for the graph store configuration."""

    ini_section = SERVICE_INI_SECTIONS["graph"]

    graph_username: Annotated[
        str, Field(alias="NB_GRAPH_USERNAME", default="DBUSER")
    ]
    graph_db: Annotated[
        str,
        Field(alias="NB_GRAPH_DB", default="repositories/my_db"),
        AfterValidator(add_prefix_to_database_name),
    ]
    graph_data: Annotated[
        str,
        Field(alias="LOCAL_GRAPH_DATA", default="./data"),
        AfterValidator(filesystem_path_is_explicit),
    ]
    graph_port_host: Annotated[
        str, Field(alias="NB_GRAPH_PORT_HOST", default="7200")
    ]
    graph_secrets_path: Annotated[
        str,
        Field(alias="NB_GRAPH_SECRETS_PATH", default="./secrets"),
        AfterValidator(filesystem_path_is_explicit),
    ]
    graph_memory: Annotated[str, Field(alias="NB_GRAPH_MEMORY", default="2G")]


class NodeAPI(BaseService):
    """Model for the node API configuration."""

    ini_section = SERVICE_INI_SECTIONS["node-api"]

    napi_tag: Annotated[str, Field(alias="NB_NAPI_TAG", default="latest")]
    return_agg: Annotated[bool, Field(alias="NB_RETURN_AGG", default=True)]
    catalog_mode: Annotated[
        bool, Field(alias="NB_CATALOG_MODE", default=False)
    ]
    napi_base_path: Annotated[
        str,
        Field(alias="NB_NAPI_BASE_PATH", default=""),
        AfterValidator(path_has_leading_slash),
    ]
    napi_domain: Annotated[
        str,
        Field(alias="NB_NAPI_DOMAIN", default=""),
        AfterValidator(domain_has_no_url_scheme),
    ]
    napi_port_host: Annotated[
        str, Field(alias="NB_NAPI_PORT_HOST", default="8000")
    ]
    napi_min_cell_size: Annotated[
        int, Field(alias="NB_MIN_CELL_SIZE", default=0)
    ]
    config: Annotated[str, Field(alias="NB_CONFIG", default="Neurobagel")]

    @model_validator(mode="after")
    def validate_return_agg_for_catalog_mode(self) -> Self:
        if self.return_agg is False and self.catalog_mode is True:
            return_agg_alias = type(self).model_fields["return_agg"].alias
            catalog_mode_alias = type(self).model_fields["catalog_mode"].alias

            logger.warning(
                f"In the INI file, {return_agg_alias}=False is incompatible with {catalog_mode_alias}=True. "
                "Catalog mode is an aggregate query mode intended to support dataset-level queries "
                "when only data dictionaries are available, so no subject-level query results can be returned. "
                f"{return_agg_alias} will be overridden to True."
            )
            self.return_agg = True
        return self


class FederationAPI(BaseService):
    """Model for the federation API configuration."""

    ini_section = SERVICE_INI_SECTIONS["federation-api"]

    fapi_tag: Annotated[str, Field(alias="NB_FAPI_TAG", default="latest")]
    fapi_base_path: Annotated[
        str,
        Field(alias="NB_FAPI_BASE_PATH", default=""),
        AfterValidator(path_has_leading_slash),
    ]
    fapi_domain: Annotated[
        str,
        Field(alias="NB_FAPI_DOMAIN", default=""),
        AfterValidator(domain_has_no_url_scheme),
    ]
    fapi_port_host: Annotated[
        str, Field(alias="NB_FAPI_PORT_HOST", default="8080")
    ]
    federate_remote_public_nodes: Annotated[
        bool, Field(alias="NB_FEDERATE_REMOTE_PUBLIC_NODES", default=True)
    ]


class Query(BaseService):
    """Model for the query tool configuration."""

    ini_section = SERVICE_INI_SECTIONS["query"]

    query_tag: Annotated[str, Field(alias="NB_QUERY_TAG", default="latest")]
    # TODO: Consider constructing this URL automatically for production portal deployments?
    api_query_url: Annotated[
        str, Field(alias="NB_API_QUERY_URL", default="http://localhost:8080")
    ]
    query_app_base_path: Annotated[
        str,
        Field(alias="NB_QUERY_APP_BASE_PATH", default="/"),
        AfterValidator(path_has_leading_slash),
    ]
    query_domain: Annotated[
        str,
        Field(alias="NB_QUERY_DOMAIN", default=""),
        AfterValidator(domain_has_no_url_scheme),
    ]
    query_port_host: Annotated[
        str, Field(alias="NB_QUERY_PORT_HOST", default="3000")
    ]
    # TODO: Ensure that this variable is not exported to the output .env if set to None
    query_header_script: Annotated[
        str | None,
        Field(
            alias="NB_QUERY_HEADER_SCRIPT",
            default=None,
        ),
    ]


class Experimental(BaseService):
    """Model for experimental configuration variables that are associated with multiple services."""

    ini_section = SERVICE_INI_SECTIONS["experimental"]

    enable_auth: Annotated[bool, Field(alias="NB_ENABLE_AUTH", default=False)]
    # TODO: Ensure that this variable is not exported to the output .env if set to None
    # NOTE: query_client_id is technically only used by the Portal profile
    query_client_id: Annotated[
        str | None, Field(alias="NB_QUERY_CLIENT_ID", default=None)
    ]


class NodeCompose(BaseService):
    """Model for the Docker Compose configuration variables for a node deployment."""

    ini_section = SERVICE_INI_SECTIONS["compose"]

    profile: Annotated[
        Literal["node"],
        Field(alias="COMPOSE_PROFILES", default="node"),
    ]
    project_name: Annotated[
        str, Field(alias="COMPOSE_PROJECT_NAME", default="neurobagel_node")
    ]


class PortalCompose(BaseService):
    """Model for the Docker Compose configuration variables for a portal deployment."""

    ini_section = SERVICE_INI_SECTIONS["compose"]

    profile: Annotated[
        Literal["portal"],
        Field(alias="COMPOSE_PROFILES", default="portal"),
    ]
    project_name: Annotated[
        str, Field(alias="COMPOSE_PROJECT_NAME", default="neurobagel_portal")
    ]


class QuickstartCompose(BaseService):
    """Model for the Docker Compose configuration variables for a test deployment."""

    ini_section = SERVICE_INI_SECTIONS["compose"]

    project_name: Annotated[
        str,
        Field(alias="COMPOSE_PROJECT_NAME", default="neurobagel_quickstart"),
    ]


class BaseProfile(BaseModel):
    """
    Base model for the configuration of a specific Neurobagel deployment profile/variant (node, portal, or quickstart),
    with custom warning logic about INI sections that are not recognized or relevant to the profile.
    """

    service_experimental: Annotated[
        Experimental,
        Field(
            alias=SERVICE_INI_SECTIONS["experimental"],
            default_factory=Experimental,
        ),
    ]

    model_config = ConfigDict(extra="ignore")

    @model_validator(mode="before")
    @classmethod
    def warn_extra_sections(cls, data):
        if isinstance(data, dict):
            if extra_sections := _get_extra_fields(cls, data):
                logger.warning(
                    f"INI file contains sections that are not recognized or used for the {cls.__name__} deployment profile:\n"
                    + "\n".join(
                        f" - {extra_section}"
                        for extra_section in extra_sections
                    )
                    + "\nThese sections will be ignored."
                )
        return data


class Node(BaseProfile):
    """Model for the production node deployment configuration."""

    service_graph: Annotated[
        Graph,
        Field(alias=SERVICE_INI_SECTIONS["graph"], default_factory=Graph),
    ]
    service_node_api: Annotated[
        NodeAPI,
        Field(alias=SERVICE_INI_SECTIONS["node-api"], default_factory=NodeAPI),
    ]
    compose: Annotated[
        NodeCompose, Field(alias="compose", default_factory=NodeCompose)
    ]


class Portal(BaseProfile):
    """Model for the production portal deployment configuration."""

    service_federation_api: Annotated[
        FederationAPI,
        Field(
            alias=SERVICE_INI_SECTIONS["federation-api"],
            default_factory=FederationAPI,
        ),
    ]
    service_query: Annotated[
        Query,
        Field(alias=SERVICE_INI_SECTIONS["query"], default_factory=Query),
    ]
    compose: Annotated[
        PortalCompose,
        Field(alias="compose", default_factory=PortalCompose),
    ]


class Quickstart(BaseProfile):
    """Model for a test deployment configuration that includes all services."""

    service_graph: Annotated[
        Graph,
        Field(alias=SERVICE_INI_SECTIONS["graph"], default_factory=Graph),
    ]
    service_node_api: Annotated[
        NodeAPI,
        Field(alias=SERVICE_INI_SECTIONS["node-api"], default_factory=NodeAPI),
    ]
    service_federation_api: Annotated[
        FederationAPI,
        Field(
            alias=SERVICE_INI_SECTIONS["federation-api"],
            default_factory=FederationAPI,
        ),
    ]
    service_query: Annotated[
        Query,
        Field(alias=SERVICE_INI_SECTIONS["query"], default_factory=Query),
    ]
    compose: Annotated[
        QuickstartCompose,
        Field(alias="compose", default_factory=QuickstartCompose),
    ]


COMPOSE_PROFILE_TO_CLASS_MAP: dict[str, type[BaseProfile]] = {
    "node": Node,
    "portal": Portal,
}
