import pytest

from configure_nb import utility as util
from configure_nb.cli import configure_nb


def test_valid_node_definition_sections_produce_correct_federation_nodes_config(
    runner,
    tmp_path,
    tmp_ini_path,
    tmp_federation_nodes_config_path,
    caplog,
):
    """
    Test that valid federation node definitions in the configuration INI are correctly parsed
    and included in the generated federation node config JSON file.
    """
    ini_content = """
[service:federation-api]
NB_FAPI_DOMAIN=myinstitute.org
NB_FAPI_BASE_PATH=/federate

[service:query]
NB_QUERY_DOMAIN=myinstitute.org

[compose]
COMPOSE_PROFILES=portal

[node:1]
NAME=Site 1 node
API_URL=https://myinstitute.org/node1

[node:2]
NAME=Site 2 node
API_URL=https://myinstitute.org/node2
"""
    expected_federation_nodes_config = [
        {
            "NodeName": "Site 1 node",
            "ApiURL": "https://myinstitute.org/node1",
        },
        {
            "NodeName": "Site 2 node",
            "ApiURL": "https://myinstitute.org/node2",
        },
    ]

    util.write_text_file(tmp_ini_path, ini_content)

    result = runner.invoke(
        configure_nb,
        [
            "--config-file",
            tmp_ini_path,
            "--output-dir",
            tmp_path,
        ],
    )

    federation_nodes_config = util.read_json(tmp_federation_nodes_config_path)

    assert result.exit_code == 0
    assert tmp_federation_nodes_config_path.exists()
    assert (
        f"{len(expected_federation_nodes_config)} internal federation node(s) will be included"
        in caplog.text
    )
    assert federation_nodes_config == expected_federation_nodes_config


def test_correct_federation_nodes_config_created_for_quickstart_ini_with_nodes_defined(
    runner,
    tmp_path,
    tmp_ini_path,
    tmp_federation_nodes_config_path,
    caplog,
):
    """
    Test that for a quickstart deployment config, valid federation node definitions
    are still correctly parsed and included in the output federation node config JSON file.
    """
    ini_content = """
[service:graph]
LOCAL_GRAPH_DATA=/data/my_first_jsonlds

[node:local]
NAME=My local node
API_URL=http://api:8000/

[node:other-site]
NAME=Other site's node
API_URL=https://myinstitute.org/othernode
"""
    expected_federation_nodes_config = [
        {"NodeName": "My local node", "ApiURL": "http://api:8000/"},
        {
            "NodeName": "Other site's node",
            "ApiURL": "https://myinstitute.org/othernode",
        },
    ]

    util.write_text_file(tmp_ini_path, ini_content)

    result = runner.invoke(
        configure_nb,
        [
            "--config-file",
            tmp_ini_path,
            "--output-dir",
            tmp_path,
        ],
    )

    federation_nodes_config = util.read_json(tmp_federation_nodes_config_path)

    assert result.exit_code == 0
    assert tmp_federation_nodes_config_path.exists()
    assert (
        f"{len(expected_federation_nodes_config)} internal federation node(s) will be included"
        in caplog.text
    )
    assert federation_nodes_config == expected_federation_nodes_config


def test_default_local_node_config_created_if_ini_missing(
    runner,
    tmp_path,
    tmp_federation_nodes_config_path,
):
    """
    Test that when no configuration INI file is provided (thus a quickstart deployment is assumed),
    a default federation node config is created containing a single node
    using the default Docker container address of the node API.
    """
    expected_federation_nodes_config = [
        {"NodeName": "Local graph 1", "ApiURL": "http://api:8000/"}
    ]

    result = runner.invoke(
        configure_nb,
        [
            "--output-dir",
            tmp_path,
        ],
    )

    federation_nodes_config = util.read_json(tmp_federation_nodes_config_path)

    assert result.exit_code == 0
    assert tmp_federation_nodes_config_path.exists()
    assert federation_nodes_config == expected_federation_nodes_config


def test_default_local_node_config_created_if_no_federation_nodes_defined_for_quickstart_deployment(
    runner,
    tmp_path,
    tmp_ini_path,
    tmp_federation_nodes_config_path,
):
    """
    Test that when COMPOSE_PROFILES is not set (thus a quickstart deployment is assumed) and no federation nodes are defined,
    a default federation node config is created containing a single node
    using the default Docker container address of the node API.
    """
    ini_content = """
[service:graph]
LOCAL_GRAPH_DATA=/data/my_first_jsonlds
"""
    expected_federation_nodes_config = [
        {"NodeName": "Local graph 1", "ApiURL": "http://api:8000/"}
    ]

    util.write_text_file(tmp_ini_path, ini_content)

    result = runner.invoke(
        configure_nb,
        [
            "--config-file",
            tmp_ini_path,
            "--output-dir",
            tmp_path,
        ],
    )

    federation_nodes_config = util.read_json(tmp_federation_nodes_config_path)

    assert result.exit_code == 0
    assert tmp_federation_nodes_config_path.exists()
    assert federation_nodes_config == expected_federation_nodes_config


def test_missing_federation_nodes_for_portal_config_emits_warning(
    runner,
    tmp_path,
    tmp_ini_path,
    tmp_dotenv_path,
    tmp_federation_nodes_config_path,
    caplog,
    propagate_info,
):
    """
    Test that when a portal deployment is specified but no internal federation nodes are defined,
    the app logs a warning but still succeeds, generating an empty federation node configuration file.
    """
    ini_content = """
[service:federation-api]
NB_FAPI_DOMAIN=myinstitute.org
NB_FAPI_BASE_PATH=/federate

[service:query]
NB_QUERY_DOMAIN=myinstitute.org

[compose]
COMPOSE_PROFILES=portal
"""

    util.write_text_file(tmp_ini_path, ini_content)

    result = runner.invoke(
        configure_nb,
        [
            "--config-file",
            tmp_ini_path,
            "--output-dir",
            tmp_path,
        ],
    )

    federation_nodes_config = util.read_json(tmp_federation_nodes_config_path)
    warnings = [
        record for record in caplog.records if record.levelname == "WARNING"
    ]

    assert result.exit_code == 0
    assert tmp_dotenv_path.exists()
    assert federation_nodes_config == []
    assert len(warnings) == 1
    assert (
        "No internal nodes were defined for query federation"
        in warnings[0].message
    )
    assert "0 internal federation node(s) will be included" in caplog.text


@pytest.mark.parametrize(
    "node_sections, expected_invalid_node_count, expected_err",
    [
        (
            """
            [node:1]
            API_URL=https://myinstitute.org/node
            """,
            1,
            ["[node:1]", "NAME", "Field required"],
        ),
        (
            """
            [node:1]
            NAME=
            API_URL=https://myinstitute.org/node
            """,
            1,
            ["[node:1]", "NAME", "cannot be an empty string"],
        ),
        (
            """
            [node:1]
            NAME=Local node
            API_URL=myinstitute.org/node
            """,
            1,
            ["[node:1]", "API_URL", "should be a valid URL"],
        ),
        (
            """
            [node:1]
            NAME=Local node
            API_URL=https://myinstitute.org/node
            EXTRA_KEY=extra_value
            """,
            1,
            ["[node:1]", "EXTRA_KEY", "Extra inputs are not permitted"],
        ),
        (
            """
            [node:1]
            NAME=Local node 1
            API_URL=myinstitute.org/node1

            [node:2]
            NAME=Local node 2
            API_URL=myinstitute.org/node2
            """,
            2,
            ["[node:1]", "[node:2]", "API_URL", "should be a valid URL"],
        ),
        (
            """
            [node:1]
            NAME=Local node 1
            API_URL=https://myinstitute.org/node1

            [node:2]
            """,
            1,
            ["[node:2]", "NAME", "API_URL", "Field required"],
        ),
    ],
)
def test_any_invalid_federation_node_definition_raises_error(
    runner,
    tmp_path,
    tmp_ini_path,
    tmp_dotenv_path,
    tmp_federation_nodes_config_path,
    caplog,
    propagate_errors,
    node_sections,
    expected_invalid_node_count,
    expected_err,
):
    """
    Test that if any node definitions are invalid, an informative error is logged and no output files are created.
    """
    ini_service_config = """
[service:federation-api]
NB_FAPI_DOMAIN=myinstitute.org
NB_FAPI_BASE_PATH=/federate

[service:query]
NB_QUERY_DOMAIN=myinstitute.org

[compose]
COMPOSE_PROFILES=portal
"""
    ini_content = "\n\n".join(
        [ini_service_config.strip(), node_sections.strip()]
    )
    util.write_text_file(tmp_ini_path, ini_content)

    result = runner.invoke(
        configure_nb,
        [
            "--config-file",
            tmp_ini_path,
            "--output-dir",
            tmp_path,
        ],
    )

    assert result.exit_code != 0
    assert not tmp_dotenv_path.exists()
    assert not tmp_federation_nodes_config_path.exists()
    assert len(caplog.records) == 1
    assert (
        f"{expected_invalid_node_count} invalid definition(s) of internal federation nodes"
        in caplog.text
    )
    for part in expected_err:
        assert part in caplog.text


def test_federation_node_sections_ignored_with_warning_for_node_deployment(
    runner,
    tmp_path,
    tmp_ini_path,
    tmp_dotenv_path,
    tmp_federation_nodes_config_path,
    caplog,
    propagate_warnings,
):
    """
    Test that when the INI file contains [node:*] sections but specifies a node deployment profile,
    these sections are treated like any other sections not recognized by the profile
    and are ignored with a warning.
    """
    ini_content = """
    [service:node-api]
    NB_NAPI_DOMAIN=testdomain.org
    NB_NAPI_BASE_PATH=/node1

    [service:graph]
    NB_GRAPH_USERNAME=testuser
    LOCAL_GRAPH_DATA=/data/test_data

    [compose]
    COMPOSE_PROFILES=node

    [node:1]
    NAME=Local node
    API_URL=https://test_domain.org/node1

    [node:2]
    NAME=Other site's node
    API_URL=https://test_domain.org/node2
    """
    expected_warning = [
        "sections that are not recognized or used for the Node deployment profile",
        "node:1",
        "node:2",
    ]

    util.write_text_file(tmp_ini_path, ini_content)

    result = runner.invoke(
        configure_nb,
        [
            "--config-file",
            tmp_ini_path,
            "--output-dir",
            tmp_path,
        ],
    )

    warnings = [
        record for record in caplog.records if record.levelname == "WARNING"
    ]

    assert result.exit_code == 0
    assert tmp_dotenv_path.exists()
    assert not tmp_federation_nodes_config_path.exists()
    assert len(warnings) == 1
    for part in expected_warning:
        assert part in warnings[0].message
