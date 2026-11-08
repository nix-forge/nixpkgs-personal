# shellcheck shell=bash
# Nix supplies builder variables and template rendering outputs.
# shellcheck disable=SC2154
runHook preInstall
mkdir -p "$out/model/huggingface"
@installModels@
tar -xzf @archives_huggingface@ -C "$out/model/huggingface"
tar -xzf @archives_gte@ -C "$out/model"
tar -xzf @archives_silero@ -C "$out/model"
tar -xzf @archives_whisper@ -C "$out/model"

# AudioMuse only loads the RoBERTa tokenizer from this cache. Removing the
# unused BERT/BART weights saves about 1.4 GB without changing inference.
find "$out/model/huggingface" -type l -print0 | while IFS= read -r -d $'\0' link; do
  target="$(readlink -f "$link")"
  cp --remove-destination "$target" "$link"
done
rm -rf \
  "$out/model/huggingface/hub/models--bert-base-uncased" \
  "$out/model/huggingface/hub/models--facebook--bart-base"
find "$out/model/huggingface/hub/models--roberta-base" -type f \
  \( -name model.safetensors -o -name pytorch_model.bin \) -delete
find "$out/model/huggingface/hub/models--roberta-base" -type f \
  -size +10M -delete

test -s "$out/model/musicnn_embedding.onnx"
test -s "$out/model/model_epoch_36.onnx.data"
test -s "$out/model/whisper-small-onnx/encoder_model.onnx"
test -s "$out/model/gte-multilingual-base/tokenizer.json"
test -z "$(find -L "$out/model" -type l -print -quit)"
runHook postInstall
