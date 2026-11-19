# Parakeet Unified EN GGUF

English speech recognition weights for runtimes supporting Parakeet Unified,
including Handy's transcribe.cpp backend. This package selects Q8_0 and installs
one unmodified model at `share/parakeet-unified-en-gguf/`.

The package exposes `modelId`, `modelFilename` and `modelFile` passthru attributes
for consumers. Handy consumers install the link using the distinct
`nix-parakeet-unified-en-0.6b-Q8_0.gguf` filename and select its stem as a local
model ID. This prevents an existing Hugging Face catalog cache from overriding
the Nix-selected weights; shared caches and other downloads remain untouched.
It contains no recognizer, downloader service or application
settings. The same data output works on Linux and macOS; GPU/backend support
belongs to the consuming inference engine.

## Updates

The repository's daily package-update workflow discovers `update.py` and opens
an update PR when the selected weights change. Source revision, version, size
and SHA-256 are generated in `source.nix`; consumers do not maintain another pin.
Preview an update from the package repository:

```sh
nix develop --command python scripts/update_packages.py \
  --package parakeet-unified-en-gguf -- --dry-run --refresh
```

Omit `--dry-run` to update the editable checkout. `--check` returns 1 when new
weights are available; `--refresh` verifies even unchanged weights. `--help`
does not contact the network. The native wrapper also accepts `--package-dir`
for callers outside the checkout and is exported through `passthru.updateScript`.

The updater resolves the public Hub's `main` once, then fetches that immutable
revision with Nix's expected SHA-256 verification. It checks size and the GGUF
header before atomically replacing the source pin, preserving permissions.
Missing files, missing digests, unsupported headers and failed transfers leave
the pin untouched. Model-card-only commits do not cause weight updates. It does
not choose another model family, quantization or filename automatically, and it
does not create Git commits or publish changes itself.

A verified transfer and GGUF header do not establish recognition quality or
compatibility with every engine version. Review model changes and use the normal
consumer deployment and Nix generation rollback. Updates take effect after the
package update is merged, the consumer's input advances and its configuration is
deployed. There is no network or model update work in the dictation path.

## Attribution and license

The original NVIDIA model uses the
[NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/).
The [GGUF conversion repository](https://huggingface.co/handy-computer/parakeet-unified-en-0.6b-gguf)
labels its conversion CC-BY-4.0. The package conservatively retains both
attributions and classifies the original model's use restrictions as nonfree;
the conversion's metadata does not replace NVIDIA's terms. The output includes
the NVIDIA agreement and its required notice. The package recipe is independent
of the workstation configuration and does not publish a public binary cache.
