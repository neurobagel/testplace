import pytest
import typer

from configure_nb import utility as util


@pytest.mark.parametrize(
    "ini_content, expected_dict",
    [
        (
            """
            [service:first-service]
            KEY1=value1
            KEY2=123

            [other-section]
            KEYA=/path/to/something
            KEYB=true
            """,
            {
                "service:first-service": {"KEY1": "value1", "KEY2": "123"},
                "other-section": {
                    "KEYA": "/path/to/something",
                    "KEYB": "true",
                },
            },
        ),
        ("", {}),
    ],
)
def test_load_ini_as_dict(tmp_ini_path, ini_content, expected_dict):
    util.write_text_file(tmp_ini_path, ini_content)
    ini_dict = util.load_ini_as_dict(tmp_ini_path)

    assert ini_dict == expected_dict


@pytest.mark.parametrize(
    "ini_content, expected_err",
    [
        (
            """
            [service:graph]
            LOCAL_GRAPH_DATA=/data/test_data

            [service:graph]
            LOCAL_GRAPH_DATA=/test_data
            """,
            ["duplicate section", "service:graph"],
        ),
        (
            """
            [service:graph]
            LOCAL_GRAPH_DATA=/data/test_data
            LOCAL_GRAPH_DATA=/test_data
            """,
            ["duplicate variable", "LOCAL_GRAPH_DATA", "service:graph"],
        ),
    ],
)
def test_duplicate_section_or_option_in_ini_raises_err(
    tmp_ini_path, propagate_errors, caplog, ini_content, expected_err
):
    util.write_text_file(tmp_ini_path, ini_content)

    with pytest.raises(typer.Exit):
        util.load_ini_as_dict(tmp_ini_path)

    assert len(caplog.records) == 1
    for part in expected_err:
        assert part in caplog.text


def test_split_federation_node_sections_from_env_vars():
    """
    Test that INI sections with the prefix for an internal federation node definition
    are correctly split from other sections.
    """
    ini_contents = {
        "service:federation-api": {
            "NB_FAPI_DOMAIN": "myinstitute.org",
            "NB_FAPI_BASE_PATH": "/federate",
        },
        "service:query": {"NB_QUERY_DOMAIN": "myinstitute.org"},
        "compose": {"COMPOSE_PROFILES": "portal"},
        "node:1": {
            "NAME": "Site 1 node",
            "API_URL": "https://myinstitute.org/node1",
        },
        "node:2": {
            "NAME": "Site 2 node",
            "API_URL": "https://myinstitute.org/node2",
        },
    }

    deployment_env_vars, federation_nodes = (
        util.split_federation_node_sections_from_env_vars(ini_contents)
    )

    assert deployment_env_vars == {
        "service:federation-api": {
            "NB_FAPI_DOMAIN": "myinstitute.org",
            "NB_FAPI_BASE_PATH": "/federate",
        },
        "service:query": {"NB_QUERY_DOMAIN": "myinstitute.org"},
        "compose": {"COMPOSE_PROFILES": "portal"},
    }
    assert federation_nodes == {
        "node:1": {
            "NAME": "Site 1 node",
            "API_URL": "https://myinstitute.org/node1",
        },
        "node:2": {
            "NAME": "Site 2 node",
            "API_URL": "https://myinstitute.org/node2",
        },
    }


@pytest.mark.parametrize(
    "federation_node_definitions, expected_invalid_node_count",
    [
        (
            {
                "node:1": {"API_URL": "https://myinstitute.org/node1"},
                "node:2": {
                    "NAME": "Local node 2",
                    "API_URL": "https://myinstitute.org/node2",
                },
            },
            1,
        ),
        (
            {
                "node:1": {"NAME": "Local node 1", "API_URL": "not a URL"},
                "node:2": {
                    "NAME": "Local node 2",
                    "API_URL": "also not a URL",
                },
            },
            2,
        ),
    ],
)
def test_validate_federation_node_definitions(
    federation_node_definitions, expected_invalid_node_count
):
    """
    Test that invalid definitions of internal federation nodes are correctly detected.
    """
    validation_errs = util.validate_federation_node_definitions(
        federation_node_definitions
    )
    assert len(validation_errs) == expected_invalid_node_count
