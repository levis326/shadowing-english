#!/usr/bin/env bash
set -euo pipefail

# Downloads the bundled Whisper model (English-only small, ggml format).
#
# Usage: tool/whisper/fetch_model.sh <output-dir>

readonly MODEL_NAME="ggml-small.en.bin"
readonly MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_NAME}"
readonly MODEL_SHA256="c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d"
readonly OUTPUT_DIR="${1:?output directory is required}"

mkdir -p "$OUTPUT_DIR"
curl --fail --location --retry 3 "$MODEL_URL" --output "$OUTPUT_DIR/$MODEL_NAME"

if command -v sha256sum >/dev/null 2>&1; then
  actual_sha="$(sha256sum "$OUTPUT_DIR/$MODEL_NAME" | awk '{print $1}')"
else
  actual_sha="$(shasum -a 256 "$OUTPUT_DIR/$MODEL_NAME" | awk '{print $1}')"
fi
if [[ "$actual_sha" != "$MODEL_SHA256" ]]; then
  echo "Whisper model checksum mismatch" >&2
  exit 1
fi

cat > "$OUTPUT_DIR/MODEL-INFO.txt" <<EOF
Model: ${MODEL_NAME}
Source: ${MODEL_URL}
SHA-256: ${MODEL_SHA256}
EOF
