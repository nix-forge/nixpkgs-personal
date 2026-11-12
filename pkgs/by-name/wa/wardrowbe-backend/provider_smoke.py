"""Exercise credential scope and real HTTP discovery using a mock transport."""

import asyncio
import json
import os
import tempfile
from pathlib import Path

import httpx
from app.services.ai_provider import (  # ty: ignore[import-not-found]
    discover_models,
    provider_headers,
)


def require(condition):
    if not condition:
        raise RuntimeError("Provider credential or discovery contract failed")


async def main():
    with tempfile.TemporaryDirectory() as directory:
        token_file = Path(directory) / "codex-token"
        token_file.write_text("public-codex-fixture-token")
        os.environ["WARDROWBE_CODEX_URL"] = "http://127.0.0.1:18182/v1"
        os.environ["WARDROWBE_CODEX_TOKEN_FILE"] = str(token_file)
        try:
            require(
                provider_headers(
                    "http://127.0.0.1:18182/v1", "http://localhost:11434/v1", "ollama"
                )["Authorization"]
                == "Bearer public-codex-fixture-token"
            )
            require(
                "Authorization"
                not in provider_headers(
                    "http://127.0.0.1:18183/v1", "http://localhost:11434/v1", "ollama"
                )
            )
        finally:
            os.environ.pop("WARDROWBE_CODEX_URL")
            os.environ.pop("WARDROWBE_CODEX_TOKEN_FILE")
    require(
        provider_headers(
            "https://api.example/v1/", "https://api.example/v1", "fixture"
        )["Authorization"]
        == "Bearer fixture"
    )
    require(
        "Authorization"
        not in provider_headers(
            "https://other.example/v1", "https://api.example/v1", "fixture"
        )
    )

    def respond(request):
        if request.url.host == "api.example":
            if request.url.path == "/v1/models":
                require(request.headers["authorization"] == "Bearer fixture")
                return httpx.Response(200, json={"data": [{"id": "cloud-model"}]})
            require("authorization" not in request.headers)
            return httpx.Response(404)
        require("authorization" not in request.headers)
        if request.url.path == "/v1/models":
            return httpx.Response(
                200, json={"data": [{"id": "llama-text"}, {"id": "local-vision"}]}
            )
        if request.url.path == "/api/tags":
            return httpx.Response(200, json={"models": []})
        if request.url.path == "/api/show":
            model = json.loads(request.content)["model"]
            return httpx.Response(
                200,
                json={
                    "capabilities": ["completion"]
                    + (["vision"] if model == "local-vision" else [])
                },
            )
        return httpx.Response(404)

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(respond), follow_redirects=False
    ) as client:
        cloud = await discover_models(
            client, "https://api.example/v1", "https://api.example/v1", "fixture"
        )
        require(cloud["available_models"] == ["cloud-model"])
        local = await discover_models(
            client, "http://local.example/v1", "https://api.example/v1", "fixture"
        )
        require(local["vision_models"] == ["local-vision"])
        require(local["text_models"] == ["llama-text", "local-vision"])


asyncio.run(main())
