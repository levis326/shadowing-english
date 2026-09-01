#!/usr/bin/env bash
set -euo pipefail

# Downloads the wav2vec2-large-960h checkpoint (torchaudio's cached .pth) and
# places it where pronunciation_server.py expects it (hub/checkpoints/...).
#
# Usage: tool/pronunciation/fetch_model.sh <output-dir>

readonly MODEL_NAME="wav2vec2_fairseq_large_ls960_asr_ls960.pth"
readonly MODEL_URL="https://download.pytorch.org/torchaudio/models/${MODEL_NAME}"
readonly MODEL_SHA256="f45e55ccb71e0f0c7dc52d519c29524213a2d41da7761f71089f11bf3ea40702"
readonly OUTPUT_DIR="${1:?output directory is required}"

sha256_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

mkdir -p "$OUTPUT_DIR/hub/checkpoints"
curl --fail --location --retry 3 \
  "$MODEL_URL" --output "$OUTPUT_DIR/hub/checkpoints/$MODEL_NAME"

actual="$(sha256_hash "$OUTPUT_DIR/hub/checkpoints/$MODEL_NAME")"
if [[ "$actual" != "$MODEL_SHA256" ]]; then
  echo "Pronunciation model checksum mismatch" >&2
  echo "expected: $MODEL_SHA256" >&2
  echo "actual:   $actual" >&2
  exit 1
fi

cat > "$OUTPUT_DIR/MODEL-INFO.txt" <<EOF
Model: wav2vec2-large-960h (torchaudio checkpoint)
Source: ${MODEL_URL}
SHA-256: ${MODEL_SHA256}
EOF
