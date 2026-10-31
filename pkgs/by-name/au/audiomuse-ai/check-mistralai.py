"""Exercise AudioMuse's SDK path with the development task runner unavailable."""

import ast
import importlib
import importlib.abc
import importlib.metadata
import json
import sys
from typing import override


class BlockInvoke(importlib.abc.MetaPathFinder):
    """Catch runtime imports even when another dependency supplies Invoke."""

    @override
    def find_spec(self, fullname, _path=None, _target=None) -> None:
        if fullname.split(".", 1)[0] == "invoke":
            raise AssertionError(
                "Mistral SDK must not depend on the Invoke task runner"
            )


sys.meta_path.insert(0, BlockInvoke())

httpx = importlib.import_module("httpx")
Mistral = importlib.import_module("mistralai").Mistral
Requirement = importlib.import_module("packaging.requirements").Requirement

distribution = importlib.metadata.distribution("mistralai")
assert all(
    Requirement(requirement).name.lower() != "invoke"
    for requirement in distribution.requires or []
), "Invoke must not remain in the installed runtime metadata"

# Inspect every shipped module, including optional SDKs that the chat smoke
# test does not reach. Fail closed if a future release adds a runtime import.
for file in distribution.files or []:
    if file.suffix != ".py":
        continue
    module = ast.parse(distribution.locate_file(file).read_text(encoding="utf-8"))
    for node in ast.walk(module):
        if isinstance(node, ast.Import):
            imports = [alias.name for alias in node.names]
        elif isinstance(node, ast.ImportFrom) and node.level == 0:
            imports = [node.module or ""]
        else:
            continue
        assert all(name.split(".", 1)[0] != "invoke" for name in imports), (
            f"{file} imports Invoke; review the SDK's runtime dependencies"
        )

requests = []


def respond(request):
    requests.append(request)
    assert request.method == "POST"
    assert request.url.path == "/v1/chat/completions"
    payload = json.loads(request.content)
    assert payload["messages"] == [{"role": "user", "content": "Describe this music"}]
    return httpx.Response(
        200,
        json={
            "id": "test-completion",
            "object": "chat.completion",
            "created": 0,
            "model": payload["model"],
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": "Instrumental jazz"},
                    "finish_reason": "stop",
                }
            ],
            "usage": {"prompt_tokens": 4, "completion_tokens": 2, "total_tokens": 6},
        },
    )


with (
    httpx.Client(transport=httpx.MockTransport(respond)) as client,
    Mistral(api_key="test-key", client=client) as sdk,
):
    completion = sdk.chat.complete(
        model="test-model",
        messages=[{"role": "user", "content": "Describe this music"}],
    )
    assert completion.choices[0].message.content == "Instrumental jazz"
assert len(requests) == 1
