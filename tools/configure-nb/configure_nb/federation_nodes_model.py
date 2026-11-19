from typing import Annotated

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    HttpUrl,
    RootModel,
    field_validator,
)

FEDERATION_NODE_SECTION_PREFIX = "node:"


class InternalFederationNode(BaseModel):
    """Model for the definition of an internal or local node to be federated by the federation API."""

    name: Annotated[
        str, Field(validation_alias="NAME", serialization_alias="NodeName")
    ]
    api_url: Annotated[
        HttpUrl,
        Field(validation_alias="API_URL", serialization_alias="ApiURL"),
    ]

    # populate_by_name allows us to still construct instances using the original Pydantic field names in code
    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    @field_validator("name")
    @classmethod
    def check_name_not_whitespace(cls, value: str) -> str:
        """
        Raise an error (will be caught as a ValidationError by Pydantic) if
        the required field is an empty string or all whitespace.
        """
        if value.strip() == "":
            raise ValueError("Field cannot be an empty string.")
        return value


class InternalFederationNodes(RootModel[list[InternalFederationNode]]):
    pass
