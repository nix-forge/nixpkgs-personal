"""Check the composed tokenizer APIs offline without downloading model weights."""

import importlib
from pathlib import Path
from tempfile import TemporaryDirectory

# These modules come from the actual composed package runtime, not the lint shell.
np = importlib.import_module("numpy")
tokenizers = importlib.import_module("tokenizers")
transformers = importlib.import_module("transformers")
unknown_symbol = "[UNK]"
padding_symbol = "[PAD]"

# Small deterministic vocabulary exercises the native backend through the same
# Transformers adapter used by CLAP. Model inference is a separate check.
backend = tokenizers.Tokenizer(
    tokenizers.models.WordLevel(
        {
            unknown_symbol: 0,
            padding_symbol: 1,
            "one": 2,
            "two": 3,
            "three": 4,
            "four": 5,
            "five": 6,
            "six": 7,
            "seven": 8,
        },
        unk_token=unknown_symbol,
    )
)
backend.pre_tokenizer = tokenizers.pre_tokenizers.Whitespace()
backend.decoder = tokenizers.decoders.WordPiece(prefix="##")
fast = transformers.PreTrainedTokenizerFast(
    tokenizer_object=backend, unk_token=unknown_symbol, pad_token=padding_symbol
)
with TemporaryDirectory(prefix="audiomuse-tokenizer-") as directory:
    fast.save_pretrained(directory)
    restored = transformers.AutoTokenizer.from_pretrained(
        directory, local_files_only=True
    )
    batch = restored(
        ["one two", "three four five six"],
        max_length=3,
        padding="max_length",
        truncation=True,
        return_tensors="np",
        add_special_tokens=False,
    )
    np.testing.assert_array_equal(batch["input_ids"], [[2, 3, 1], [4, 5, 6]])
    np.testing.assert_array_equal(batch["attention_mask"], [[1, 1, 0], [1, 1, 1]])
    assert restored.decode([2, 3]) == "one two"
    chunks = restored(
        "one two three four five six seven",
        max_length=3,
        stride=1,
        truncation=True,
        return_overflowing_tokens=True,
        add_special_tokens=False,
    )
    assert chunks["input_ids"] == [[2, 3, 4], [4, 5, 6], [6, 7, 8]]
    assert chunks["overflow_to_sample_mapping"] == [0, 0, 0]
    # Lyrics embedding uses the native Tokenizer.from_file API directly.
    native = tokenizers.Tokenizer.from_file(str(Path(directory) / "tokenizer.json"))
    native.no_padding()
    native.enable_truncation(max_length=3, stride=1)
    encoded = native.encode("one two three four five six seven")
    assert encoded.ids == [2, 3, 4]
    assert [part.ids for part in encoded.overflowing] == [[4, 5, 6], [6, 7, 8]]
print("Offline Transformers/native tokenization, padding, overflow and reload passed")
