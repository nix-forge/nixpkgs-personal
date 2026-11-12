"""Validate generated artifacts in an isolated build or VM fixture."""

import importlib
import importlib.metadata
import sys
from pathlib import Path

from packaging.requirements import Requirement
from packaging.version import Version

# File execution must preserve the former stdin program's working-directory imports.
sys.path.insert(0, str(Path.cwd() / "native-build"))
sys.path.insert(1, str(Path.cwd()))
for module_name in (
    "flask",
    "google.genai",
    "huggingface_hub",
    "librosa",
    "mistralai",
    "mutagen",
    "numkong",
    "onnxruntime",
    "psycopg2",
    "sentencepiece",
    "tokenizers",
    "transformers",
    "app_auth",
    "numeric_bootstrap",
):
    importlib.import_module(module_name)
service_roles = importlib.import_module("service_roles")
launcher = importlib.import_module("linux.launcher")
deps = importlib.import_module("transformers.dependency_versions_table").deps

package_version = importlib.metadata.version
assert package_version("google-genai") == "@source_python_googleGenai_version@"
assert package_version("mistralai") == "@source_python_mistralai_version@"
assert package_version("transformers") == "@source_python_transformers_version@"
assert package_version("huggingface-hub") == "@source_python_huggingfaceHub_version@"
tokenizers_requirement = Requirement(deps["tokenizers"])
assert deps["tokenizers"] == "@source_python_transformers_tokenizersRequirement@"
assert tokenizers_requirement.specifier.contains(
    package_version("tokenizers"), prereleases=True
)
assert Version(package_version("tokenizers")) >= Version("0.22.0")
assert service_roles.ROLE_FLASK == "flask"
assert launcher.WEB_URL == "http://127.0.0.1:8000"
