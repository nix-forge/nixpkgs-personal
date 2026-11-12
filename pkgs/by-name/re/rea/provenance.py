"""Bind npm releases without gitHead to verified upstream build provenance."""

from __future__ import annotations

import base64
import json
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable

    from sigstore.verify.policy import VerificationPolicy

PROVENANCE_TYPE = "https://slsa.dev/provenance/v1"
REPOSITORY = "https://github.com/morluto/rea"
WORKFLOW_PATH = ".github/workflows/release.yml"
WORKFLOW_REF = "refs/heads/main"
SHA512_DIGEST_BYTES = 64


def verification_policy(revision: str) -> VerificationPolicy:
    """Build the reviewed certificate policy independently of bundle contents.

    Returns:
        A policy requiring the release workflow, repository, issuer, and commit.

    """
    # Lazy imports keep --help and gitHead-only updates usable without sigstore.
    from sigstore.verify.policy import (  # ruff: ignore[import-outside-top-level]
        AllOf,
        GitHubWorkflowRepository,
        GitHubWorkflowSHA,
        Identity,
    )

    return AllOf([
        Identity(
            identity=f"{REPOSITORY}/{WORKFLOW_PATH}@{WORKFLOW_REF}",
            issuer="https://token.actions.githubusercontent.com",
        ),
        GitHubWorkflowRepository("morluto/rea"),
        GitHubWorkflowSHA(revision),
    ])


def unique_object(pairs: list[tuple[str, object]]) -> dict:
    """Reject duplicate JSON members instead of silently choosing an identity.

    Returns:
        A dictionary with unique keys.

    Raises:
        ValueError: A JSON object contains duplicate members.

    """
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Ambiguous provenance JSON object")
        result[key] = value
    return result


def verified_statement(bundle: dict, revision: str) -> dict:
    """Verify signature, certificate policy, and transparency before parsing.

    Returns:
        The authenticated in-toto statement.

    Raises:
        ValueError: The authenticated payload has an unexpected content type.
        TypeError: The authenticated statement is not an object.

    """
    from sigstore.models import Bundle  # ruff: ignore[import-outside-top-level]
    from sigstore.verify import Verifier  # ruff: ignore[import-outside-top-level]

    parsed_bundle = Bundle.from_json(json.dumps(bundle))
    payload_type, payload = Verifier.production().verify_dsse(
        parsed_bundle, verification_policy(revision)
    )
    if payload_type != "application/vnd.in-toto+json":
        raise ValueError("Unexpected verified provenance payload type")
    statement = json.loads(payload, object_pairs_hook=unique_object)
    if not isinstance(statement, dict):
        raise TypeError("Expected a verified provenance statement object")
    return statement


def registry_digest(metadata: dict) -> str:
    """Decode the single reviewed npm SHA512 integrity value.

    Returns:
        The digest in the hexadecimal encoding used by provenance subjects.

    Raises:
        ValueError: Registry integrity is missing, malformed, or not SHA512.
        TypeError: Registry distribution metadata is not an object.

    """
    distribution = metadata.get("dist")
    if not isinstance(distribution, dict):
        raise TypeError("Expected registry distribution integrity")
    integrity = distribution.get("integrity", "")
    if not isinstance(integrity, str) or not integrity.startswith("sha512-"):
        raise ValueError("Expected one SHA512 registry integrity digest")
    try:
        digest = base64.b64decode(integrity.removeprefix("sha512-"), validate=True)
    except ValueError as error:
        raise ValueError("Invalid registry integrity digest") from error
    if len(digest) != SHA512_DIGEST_BYTES:
        raise ValueError("Invalid registry SHA512 digest length")
    return digest.hex()


def validate_statement(statement: dict, metadata: dict, revision: str) -> None:
    """Bind an authenticated statement to the exact npm subject and Git source.

    Raises:
        ValueError: The statement has an unknown, conflicting, or missing identity.
        TypeError: A required statement section is not an object.

    """
    if (
        statement.get("_type") != "https://in-toto.io/Statement/v1"
        or statement.get("predicateType") != PROVENANCE_TYPE
    ):
        raise ValueError("Unexpected verified provenance statement type")
    expected_subject = [
        {
            "name": f"pkg:npm/rea-agents@{metadata['version']}",
            "digest": {"sha512": registry_digest(metadata)},
        }
    ]
    if statement.get("subject") != expected_subject:
        raise ValueError("Verified provenance subject disagrees with the npm release")
    predicate = statement.get("predicate")
    if not isinstance(predicate, dict):
        raise TypeError("Expected a verified provenance predicate object")
    definition = predicate.get("buildDefinition")
    if not isinstance(definition, dict):
        raise TypeError("Expected a verified provenance build definition")
    if definition.get("buildType") != (
        "https://slsa-framework.github.io/github-actions-buildtypes/workflow/v1"
    ):
        raise ValueError("Unexpected verified provenance build type")
    external = definition.get("externalParameters")
    if not isinstance(external, dict):
        raise TypeError("Expected verified provenance workflow parameters")
    workflow = external.get("workflow")
    if workflow != {
        "repository": REPOSITORY,
        "path": WORKFLOW_PATH,
        "ref": WORKFLOW_REF,
    }:
        raise ValueError("Verified provenance workflow identity changed")
    # The reviewed workflow has one source dependency. Additional or conflicting
    # mappings require review even if one entry happens to match the release.
    if definition.get("resolvedDependencies") != [
        {
            "uri": f"git+{REPOSITORY}@{WORKFLOW_REF}",
            "digest": {"gitCommit": revision},
        }
    ]:
        raise ValueError("Verified provenance source commit disagrees with the release")


def verify_registry_source(
    metadata: dict, revision: str, fetch_json: Callable[[str], dict]
) -> None:
    """Preserve strict gitHead checks, falling back only to verified provenance.

    Raises:
        ValueError: Registry identity disagrees or provenance is missing/ambiguous.
        TypeError: The registry attestations collection is not a list.

    """
    if "gitHead" in metadata:
        if metadata["gitHead"] != revision:
            raise ValueError("Registry release and public source commit disagree")
        return
    # Never trust a registry-provided URL or workflow identity for this fallback.
    attestations = fetch_json(
        "https://registry.npmjs.org/-/npm/v1/attestations/rea-agents@"
        + metadata["version"]
    )
    entries = attestations.get("attestations")
    if not isinstance(entries, list):
        raise TypeError("Expected a registry attestations list")
    matches = [
        entry
        for entry in entries
        if isinstance(entry, dict) and entry.get("predicateType") == PROVENANCE_TYPE
    ]
    if len(matches) != 1 or not isinstance(matches[0].get("bundle"), dict):
        raise ValueError("Expected exactly one SLSA provenance attestation")
    statement = verified_statement(matches[0]["bundle"], revision)
    validate_statement(statement, metadata, revision)
