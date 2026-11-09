"""Verify that the selected TLS provider no longer carries obsolete WebPKI."""

import json
import sys
from pathlib import Path


def check(metadata: dict, target: str) -> None:
    """Reject affected parser versions while preserving the selected provider.

    Raises:
        ValueError: If the resolved graph violates the provider contract.

    """
    packages = metadata["packages"]
    parsers = [item for item in packages if item["name"] == "rustls-webpki"]
    for parser in parsers:
        version = parser["version"]
        if "-" in version or tuple(map(int, version.split("."))) < (0, 103, 13):
            raise ValueError(f"Affected WebPKI remains: {version}")
    providers = [item for item in packages if item["name"] == "rustls-rustcrypto"]
    # This crate and its download dependencies are intentionally native-only.
    if target == "wasm32-unknown-unknown":
        if providers:
            raise ValueError("The native-only download provider entered the web graph")
        print("Native-only provider absent; no affected WebPKI in the web graph")
        return
    if len(providers) != 1:
        raise ValueError("Expected one RustCrypto provider")
    provider = providers[0]
    if provider["version"] != "0.0.2-alpha" or provider["source"] is not None:
        raise ValueError("Expected the pinned local provider")
    if any(item["name"] == "rustls-webpki" for item in provider["dependencies"]):
        raise ValueError("The provider must obtain identifiers from pki-types")
    if not parsers:
        raise ValueError("The actual Rustls certificate verifier must remain")
    nodes = {item["id"]: item for item in metadata["resolve"]["nodes"]}
    if not {"std", "tls12", "zeroize"}.issubset(nodes[provider["id"]]["features"]):
        raise ValueError("The provider's default security features changed")
    print("Pinned RustCrypto provider and patched certificate verifier validated")


if __name__ == "__main__":
    check(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")), sys.argv[2])
