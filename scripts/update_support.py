"""Shared helpers for package updater scripts."""

from __future__ import annotations

import os
import ssl
from pathlib import Path
from typing import Final

HTTPS_CERT_CANDIDATES: Final = (
    os.environ.get("SSL_CERT_FILE"),
    os.environ.get("NIX_SSL_CERT_FILE"),
    "/etc/ssl/cert.pem",
    "/etc/ssl/certs/ca-certificates.crt",
    "/etc/pki/tls/certs/ca-bundle.crt",
    "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt",
)


def github_api_headers(user_agent: str) -> dict[str, str]:
    """Return standard GitHub API headers with optional token auth.

    ``GH_TOKEN`` is used by the GitHub CLI and package-update workflow;
    ``GITHUB_TOKEN`` is supported as the native Actions equivalent.  The
    unauthenticated fallback keeps local updates usable when no GitHub
    credentials are configured, while authenticated runs avoid low API rate
    limits.

    Returns:
        GitHub API headers, including an authorization header when a token is
        available in the environment.

    """
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": user_agent,
        "X-GitHub-Api-Version": "2022-11-28",
    }
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def https_context() -> ssl.SSLContext:
    """Return an SSL context using the first readable CA bundle.

    Returns:
        SSL context configured with the first readable CA bundle, or the
        default OpenSSL context if none is available.

    """
    for candidate in HTTPS_CERT_CANDIDATES:
        if candidate and Path(candidate).is_file():
            return ssl.create_default_context(cafile=candidate)

    return ssl.create_default_context()


HTTPS_CONTEXT: Final = https_context()
