"""Check the optional native image processing imports and CPU provider."""

import importlib

importlib.import_module("rembg")
onnxruntime = importlib.import_module("onnxruntime")
assert "CPUExecutionProvider" in onnxruntime.get_available_providers()
