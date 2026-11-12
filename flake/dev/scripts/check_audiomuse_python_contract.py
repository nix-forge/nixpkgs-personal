"""Validate generated artifacts in an isolated build or VM fixture."""

import importlib
import importlib.metadata
import os
import sys

from packaging.requirements import Requirement
from packaging.version import Version

source = os.environ["AUDIOMUSE_SOURCE"]
sys.path.insert(0, f"{source}/native-build")
sys.path.insert(1, source)

# Import optional providers to prove that the packaged runtime can load them.
for module_name in (
    "google.genai",
    "huggingface_hub",
    "mistralai",
    "onnxruntime",
    "safetensors",
    "tokenizers",
    "transformers",
    "app_auth",
    "numeric_bootstrap",
):
    importlib.import_module(module_name)
service_roles = importlib.import_module("service_roles")
deps = importlib.import_module("transformers.dependency_versions_table").deps
launcher = importlib.import_module("linux.launcher")

package_version = importlib.metadata.version
assert package_version("google-genai") == "@source_python_googleGenai_version@"
assert package_version("huggingface-hub") == "@source_python_huggingfaceHub_version@"
assert package_version("mistralai") == "@source_python_mistralai_version@"
assert package_version("transformers") == "@source_python_transformers_version@"
assert deps["tokenizers"] == "@source_python_transformers_tokenizersRequirement@"
tokenizers_requirement = Requirement(deps["tokenizers"])
assert tokenizers_requirement.specifier.contains(
    package_version("tokenizers"), prereleases=True
)
assert Version(package_version("tokenizers")) >= Version("0.22.0")
assert package_version("onnxruntime")
assert service_roles.ROLE_FLASK == "flask"
assert launcher.WEB_URL == "http://127.0.0.1:8000"
