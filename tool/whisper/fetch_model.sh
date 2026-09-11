#!/usr/bin/env bash
set -euo pipefail

# 注意：应用已改为在「设置 → 本地模型」中在线下载模型，CI 不再调用本脚本。
# 这里保留给需要离线打包（把模型放在 exe 旁的 whisper/ 目录）的场景。

# Downloads the bundled Whisper model (multilingual small, ggml format).
#
# Usage: tool/whisper/fetch_model.sh <output-dir>
#
# The download goes through tool/common/hf_download.sh so Hugging Face rate
# limiting (HTTP 429) on shared CI runners is retried and can use HF_TOKEN.

readonly MODEL_NAME="ggml-small.bin"
readonly MODEL_REPO_PATH="ggerganov/whisper.cpp/resolve/main/${MODEL_NAME}"
readonly MODEL_URL="https://huggingface.co/${MODEL_REPO_PATH}"
readonly MODEL_SHA256="1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
readonly OUTPUT_DIR="${1:?output directory is required}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/hf_download.sh
source "${script_dir}/../common/hf_download.sh"

mkdir -p "$OUTPUT_DIR"
hf_download "$MODEL_REPO_PATH" "$OUTPUT_DIR/$MODEL_NAME"

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
