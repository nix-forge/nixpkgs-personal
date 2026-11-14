"""Authenticate browser routes and exercise saved text and vision model routing."""

import asyncio
import json
import os
import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import httpx
from app.api import preferences  # ty: ignore[import-not-found]
from app.services.ai_service import AIService  # ty: ignore[import-not-found]
from app.utils.locale import DEFAULT_LOCALE  # ty: ignore[import-not-found]
from fastapi import FastAPI, HTTPException, status  # ty: ignore[import-not-found]
from fastapi.testclient import TestClient  # ty: ignore[import-not-found]
from PIL import Image


def require(condition):
    if not condition:
        raise RuntimeError("Browser AI integration contract failed")


def browser_routes():
    app = FastAPI()
    app.include_router(preferences.router)
    user = SimpleNamespace(id="00000000-0000-4000-8000-000000000001")
    app.dependency_overrides[preferences.get_current_user] = lambda: user
    with TestClient(app) as client:
        with patch.dict(os.environ, {}, clear=True):
            require(
                client.get("/users/me/preferences/openai/status").json()["enabled"]
                is False
            )
            require(
                client.post("/users/me/preferences/openai/login").status_code
                == status.HTTP_503_SERVICE_UNAVAILABLE
            )

        def respond(request):
            require(request.url.params["user"] == str(user.id))
            require(request.url.host == "localhost")
            if request.url.path == "/login":
                require(request.url.params["method"] in {"browser", "device"})
            if request.url.path == "/status":
                return httpx.Response(
                    200,
                    json={"enabled": True, "connected": False, "models": ["fixture"]},
                )
            return httpx.Response(
                403, json={"detail": "Another Wardrowbe user manages this connection"}
            )

        with (
            patch.dict(
                os.environ,
                {
                    "WARDROWBE_CODEX_SOCKET": "/run/fixture/control.sock",
                    "WARDROWBE_CODEX_URL": "http://127.0.0.1:18182/v1",
                },
            ),
            patch.object(
                preferences.httpx,
                "AsyncHTTPTransport",
                return_value=httpx.MockTransport(respond),
            ) as transport,
        ):
            result = client.get("/users/me/preferences/openai/status")
            require(result.status_code == status.HTTP_200_OK)
            require(result.json()["endpoint"] == "http://127.0.0.1:18182/v1")
            transport.assert_called_with(uds="/run/fixture/control.sock")
            for action in ("login", "disconnect"):
                require(
                    client.post(f"/users/me/preferences/openai/{action}").status_code
                    == status.HTTP_403_FORBIDDEN
                )

            require(
                client.post(
                    "/users/me/preferences/openai/login?method=device"
                ).status_code
                == status.HTTP_403_FORBIDDEN
            )
            require(
                client.post(
                    "/users/me/preferences/openai/login?method=invalid"
                ).status_code
                == status.HTTP_422_UNPROCESSABLE_ENTITY
            )

        def reject():
            raise HTTPException(401, "Authentication required")

        app.dependency_overrides[preferences.get_current_user] = reject
        for action in ("status", "login", "disconnect"):
            method = client.get if action == "status" else client.post
            require(
                method(f"/users/me/preferences/openai/{action}").status_code
                == status.HTTP_401_UNAUTHORIZED
            )


async def saved_models():
    endpoints = [
        {
            "url": "http://fixture.example/v1",
            "name": "fixture",
            "enabled": True,
            "vision_model": "chosen-vision",
            "text_model": "chosen-text",
        }
    ]
    service = AIService(endpoints=endpoints)
    seen = []

    def respond(request):
        require(request.url.host == "fixture.example")
        body = json.loads(request.content)
        seen.append(body["model"])
        content = (
            '{"type":"shirt","primary_color":"blue","confidence":0.9}'
            if body["model"] == "chosen-vision"
            else "fixture outfit"
        )
        return httpx.Response(
            200,
            json={
                "model": body["model"],
                "choices": [{"message": {"content": content}, "finish_reason": "stop"}],
            },
        )

    original = httpx.AsyncClient

    def client(**kwargs):
        require(kwargs.get("follow_redirects") is False)
        return original(transport=httpx.MockTransport(respond), **kwargs)

    with patch("app.services.ai_service.httpx.AsyncClient", side_effect=client):
        require(await service.generate_text("suggest an outfit") == "fixture outfit")
        with tempfile.TemporaryDirectory() as directory:
            image = Path(directory) / "shirt.png"
            Image.new("RGB", (8, 8)).save(image)
            tags = await service.analyze_image(image, locale=DEFAULT_LOCALE)
            require(tags.type == "shirt")
    require(seen[0] == "chosen-text")
    require(bool(seen[1:]) and all(model == "chosen-vision" for model in seen[1:]))


browser_routes()
asyncio.run(saved_models())
