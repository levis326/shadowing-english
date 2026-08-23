#!/usr/bin/env bash
set -euo pipefail

# Downloads the bundled NLLB-200-distilled-600M CTranslate2 int8 model.
#
# Usage: tool/nllb/fetch_model.sh <output-dir>
#
# The model directory is later bundled next to the `nllb-translate` binary
# (see desktop_nllb.dart). The CTranslate2 model directory contains:
#   model.bin               int8 weights (the C++ loader reads the model spec
#                           directly from this binary file)
#   shared_vocabulary.json  token <-> id vocabulary
#   sentencepiece.bpe.model SentencePiece tokenizer (used by nllb-translate)
#   config.json             auxiliary config (optional but kept for completeness)

readonly REPO="mijuanlo/nllb-200-distilled-600M-ct2-int8"
readonly BASE="https://huggingface.co/${REPO}/resolve/main"
readonly OUTPUT_DIR="${1:?output directory is required}"

readonly FILES=(
  model.bin
  shared_vocabulary.json
  sentencepiece.bpe.model
  config.json
)

# SHA-256 of each file (the LFS oid exposed by the Hugging Face `x-linked-etag`).
sha256_of() {
  case "$1" in
    model.bin)
      echo "398726640cc2a02cc6a35277fa3cf2159ce8a1a66b48aa1b6c8837a47e3dd00c"
      ;;
    shared_vocabulary.json)
      echo "af6771314c673db7660640e91062e5fee96eeb2a"
      ;;
    sentencepiece.bpe.model)
      echo "14bb8dfb35c0ffdea7bc01e56cea38b9e3d5efcdcb9c251d6b40538e1aab555a"
      ;;
    config.json)
      echo "b68f534191ebc23c89dbc07de9732c2495366bb1"
      ;;
    *)
      echo "" && return 1
      ;;
  esac
}

sha256_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

mkdir -p "$OUTPUT_DIR"
for file in "${FILES[@]}"; do
  curl --fail --location --retry 3 "$BASE/$file" --output "$OUTPUT_DIR/$file"
done

for file in "${FILES[@]}"; do
  expected="$(sha256_of "$file")"
  actual="$(sha256_hash "$OUTPUT_DIR/$file")"
  if [[ "$actual" != "$expected" ]]; then
    echo "NLLB model file checksum mismatch: $file" >&2
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    exit 1
  fi
done

cat > "$OUTPUT_DIR/MODEL-INFO.txt" <<EOF
Model: nllb-200-distilled-600M (CTranslate2 int8)
Source: https://huggingface.co/${REPO}
Original model: facebook/nllb-200-distilled-600M
License: CC-BY-NC 4.0 (non-commercial)
EOF
