"""Exercise authenticated npm/source binding and strict failure paths."""

import base64
import copy
import json
from datetime import UTC, datetime, timedelta
from unittest.mock import Mock, patch

import provenance
import pytest

REVISION = "a" * 40
METADATA: dict = {
    "version": "6.8.0",
    "dist": {"integrity": "sha512-" + base64.b64encode(b"x" * 64).decode()},
}
STATEMENT: dict = {
    "_type": "https://in-toto.io/Statement/v1",
    "predicateType": provenance.PROVENANCE_TYPE,
    "subject": [
        {
            "name": "pkg:npm/rea-agents@6.8.0",
            "digest": {"sha512": (b"x" * 64).hex()},
        }
    ],
    "predicate": {
        "buildDefinition": {
            "buildType": "https://slsa-framework.github.io/github-actions-buildtypes/workflow/v1",
            "externalParameters": {
                "workflow": {
                    "repository": provenance.REPOSITORY,
                    "path": provenance.WORKFLOW_PATH,
                    "ref": provenance.WORKFLOW_REF,
                }
            },
            "resolvedDependencies": [
                {
                    "uri": f"git+{provenance.REPOSITORY}@{provenance.WORKFLOW_REF}",
                    "digest": {"gitCommit": REVISION},
                }
            ],
        }
    },
}
ATTESTATIONS: dict = {
    "attestations": [{"predicateType": provenance.PROVENANCE_TYPE, "bundle": {}}]
}


def test_absent_git_head_accepts_only_verified_matching_statement():
    fetch = Mock(return_value=ATTESTATIONS)
    with patch.object(
        provenance, "verified_statement", return_value=STATEMENT
    ) as verify:
        provenance.verify_registry_source(METADATA, REVISION, fetch)
    verify.assert_called_once_with({}, REVISION)
    fetch.assert_called_once_with(
        "https://registry.npmjs.org/-/npm/v1/attestations/rea-agents@6.8.0"
    )


@pytest.mark.parametrize("git_head", ["b" * 40, None, ""])
def test_present_mismatching_git_head_never_falls_back(git_head):
    fetch = Mock()
    with (
        patch.object(provenance, "verified_statement") as verify,
        pytest.raises(ValueError, match="disagree"),
    ):
        provenance.verify_registry_source(
            {**METADATA, "gitHead": git_head}, REVISION, fetch
        )
    verify.assert_not_called()
    fetch.assert_not_called()


def test_present_matching_git_head_does_not_require_provenance():
    fetch = Mock()
    provenance.verify_registry_source(
        {**METADATA, "gitHead": REVISION}, REVISION, fetch
    )
    fetch.assert_not_called()


@pytest.mark.parametrize(
    "attestations",
    [
        {},
        {"attestations": None},
        {"attestations": []},
        {"attestations": ATTESTATIONS["attestations"] * 2},
        {
            "attestations": [
                {"predicateType": "https://registry.npmjs.org/attestation/v1"}
            ]
        },
        {
            "attestations": [
                {"predicateType": provenance.PROVENANCE_TYPE, "bundle": None}
            ]
        },
    ],
)
def test_missing_or_ambiguous_provenance_rejected_before_verification(attestations):
    with (
        patch.object(provenance, "verified_statement") as verify,
        pytest.raises(
            (ValueError, TypeError), match=r"Expected.*(attestations|attestation)"
        ),
    ):
        provenance.verify_registry_source(
            METADATA, REVISION, Mock(return_value=attestations)
        )
    verify.assert_not_called()


def test_signature_verification_failure_cannot_supply_payload_identity():
    with (
        patch.object(
            provenance, "verified_statement", side_effect=ValueError("bad signature")
        ),
        patch.object(provenance, "validate_statement") as validate,
        pytest.raises(ValueError, match="bad signature"),
    ):
        provenance.verify_registry_source(
            METADATA, REVISION, Mock(return_value=ATTESTATIONS)
        )
    validate.assert_not_called()


@pytest.mark.parametrize(
    ("path", "replacement"),
    [
        (("_type",), "https://in-toto.io/Statement/v0.1"),
        (("predicateType",), "unknown"),
        (("subject",), []),
        (("subject",), STATEMENT["subject"] * 2),
        (("subject", 0, "name"), "pkg:npm/other@6.8.0"),
        (("subject", 0, "name"), "pkg:npm/rea-agents@6.8.1"),
        (("subject", 0, "digest", "sha512"), "0" * 128),
        (("predicate",), None),
        (("predicate", "buildDefinition"), None),
        (("predicate", "buildDefinition", "buildType"), "unknown"),
        (("predicate", "buildDefinition", "externalParameters"), None),
        (
            (
                "predicate",
                "buildDefinition",
                "externalParameters",
                "workflow",
                "repository",
            ),
            "https://github.com/other/rea",
        ),
        (
            ("predicate", "buildDefinition", "externalParameters", "workflow", "path"),
            ".github/workflows/other.yml",
        ),
        (
            ("predicate", "buildDefinition", "externalParameters", "workflow", "ref"),
            "refs/heads/other",
        ),
        (("predicate", "buildDefinition", "resolvedDependencies"), []),
        (
            ("predicate", "buildDefinition", "resolvedDependencies"),
            STATEMENT["predicate"]["buildDefinition"]["resolvedDependencies"] * 2,
        ),
        (
            ("predicate", "buildDefinition", "resolvedDependencies", 0, "uri"),
            "git+https://github.com/other/rea@refs/heads/main",
        ),
        (
            (
                "predicate",
                "buildDefinition",
                "resolvedDependencies",
                0,
                "digest",
                "gitCommit",
            ),
            "b" * 40,
        ),
    ],
)
def test_authenticated_but_wrong_or_ambiguous_identity_rejected(path, replacement):
    statement = copy.deepcopy(STATEMENT)
    parent = statement
    for key in path[:-1]:
        parent = parent[key]
    parent[path[-1]] = replacement
    with pytest.raises((ValueError, TypeError), match=r"(?i)provenance"):
        provenance.validate_statement(statement, METADATA, REVISION)


@pytest.mark.parametrize("integrity", [None, "sha256-AAAA", "sha512-!", "sha512-AAAA"])
def test_invalid_registry_integrity_rejected(integrity):
    metadata = {**METADATA, "dist": {"integrity": integrity}}
    with pytest.raises(ValueError, match="registry"):
        provenance.validate_statement(STATEMENT, metadata, REVISION)


def test_duplicate_statement_members_are_rejected():
    with pytest.raises(ValueError, match="Ambiguous"):
        json.loads(
            '{"subject": [], "subject": []}', object_pairs_hook=provenance.unique_object
        )


@pytest.mark.parametrize(
    "field", [None, "identity", "issuer", "repository", "revision"]
)
def test_certificate_policy_requires_exact_workflow_issuer_repository_and_sha(field):
    pytest.importorskip("sigstore")
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.asymmetric import ec
    from sigstore.errors import VerificationError

    values = {
        "identity": f"{provenance.REPOSITORY}/{provenance.WORKFLOW_PATH}@{provenance.WORKFLOW_REF}",
        "issuer": "https://token.actions.githubusercontent.com",
        "repository": "morluto/rea",
        "revision": REVISION,
    }
    if field is not None:
        values[field] = "unexpected-identity"
    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(x509.NameOID.COMMON_NAME, "fixture")])
    now = datetime.now(UTC)
    builder = (
        x509
        .CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(1)
        .not_valid_before(now)
        .not_valid_after(now + timedelta(days=1))
        .add_extension(
            x509.SubjectAlternativeName([
                x509.UniformResourceIdentifier(values["identity"])
            ]),
            critical=False,
        )
    )
    for suffix, value in [
        ("1", values["issuer"]),
        ("3", values["revision"]),
        ("5", values["repository"]),
    ]:
        builder = builder.add_extension(
            x509.UnrecognizedExtension(
                x509.ObjectIdentifier(f"1.3.6.1.4.1.57264.1.{suffix}"), value.encode()
            ),
            critical=False,
        )
    certificate = builder.sign(key, hashes.SHA256())
    policy = provenance.verification_policy(REVISION)
    if field is None:
        policy.verify(certificate)
    else:
        with pytest.raises(VerificationError):
            policy.verify(certificate)


@pytest.mark.parametrize(
    ("payload_type", "payload"),
    [
        ("text/plain", b"{}"),
        ("application/vnd.in-toto+json", b"[]"),
        ("application/vnd.in-toto+json", b'{"subject": [], "subject": []}'),
    ],
)
def test_verified_payload_type_and_shape_are_checked(payload_type, payload):
    pytest.importorskip("sigstore")
    with (
        patch("sigstore.models.Bundle.from_json", return_value=Mock()),
        patch("sigstore.verify.Verifier.production") as production,
    ):
        production.return_value.verify_dsse.return_value = (payload_type, payload)
        with pytest.raises(
            (ValueError, TypeError), match=r"payload type|statement object|Ambiguous"
        ):
            provenance.verified_statement({}, REVISION)


def test_actual_sigstore_verification_error_is_not_swallowed():
    pytest.importorskip("sigstore")
    from sigstore.errors import VerificationError

    with (
        patch("sigstore.models.Bundle.from_json", return_value=Mock()),
        patch("sigstore.verify.Verifier.production") as production,
    ):
        production.return_value.verify_dsse.side_effect = VerificationError(
            "untrusted signature"
        )
        with pytest.raises(VerificationError, match="untrusted signature"):
            provenance.verified_statement({}, REVISION)


def test_malformed_sigstore_bundle_fails_before_trust_root_fetch():
    pytest.importorskip("sigstore")
    from sigstore.models import InvalidBundle

    with (
        patch("sigstore.verify.Verifier.production") as production,
        pytest.raises(InvalidBundle),
    ):
        provenance.verified_statement({}, REVISION)
    production.assert_not_called()
