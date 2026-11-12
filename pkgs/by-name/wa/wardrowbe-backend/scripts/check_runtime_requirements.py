"""Validate generated artifacts in an isolated build or VM fixture."""

import hashlib
import pathlib
import ssl
import sys
from importlib.metadata import distributions, version
from importlib.resources import files

from packaging.requirements import Requirement

# Upstream keeps its test dependencies in this same file. They are not
# runtime requirements of the deployed API or workers.
test_dependencies = {"pytest", "pytest-asyncio", "pytest-cov", "aiosqlite", "pyyaml"}
with pathlib.Path(sys.argv[1]).open(encoding="utf-8") as stream:
    for raw_line in stream:
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        requirement = Requirement(line)
        if requirement.name.lower() in test_dependencies:
            continue
        if requirement.marker is not None and not requirement.marker.evaluate():
            continue
        installed = version(requirement.name)
        if not requirement.specifier.contains(installed):
            raise RuntimeError(
                f"Unsatisfied runtime requirement: {requirement}; installed {installed}"
            )

# The selected environment must contain one certificate package and metadata set.
if len(list(distributions(name="certifi"))) != 1:
    raise RuntimeError(
        "Application environment has missing or duplicate certifi metadata"
    )

# Validate the bundled trust update even when an explicit host CA override exists.
# GHSA-6q48-6c7w-9gw2 removes emSign ECC Root CA-G3; retain other trust roots.
bundle = files("certifi").joinpath("cacert.pem").read_text(encoding="ascii")
context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
context.load_verify_locations(cadata=bundle)
fingerprints = {
    hashlib.sha256(certificate).hexdigest()
    for certificate in context.get_ca_certs(binary_form=True)
}
if "86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b" in fingerprints:
    raise RuntimeError("certifi bundle retains the removed emSign ECC Root CA-G3")
if (
    "40f6af0346a99aa1cd1d555a4e9cce62c7f9634603ee406615833dc8c8d00367"
    not in fingerprints
):
    raise RuntimeError("certifi bundle is missing retained trust roots")
