#!/usr/bin/env bash
set -euo pipefail

# Downloads the bundled NLLB-200-distilled-1.3B CTranslate2 int8 model.
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
#
# The 1.3B model translates noticeably better than the previous 600M one
# (the bundled package grows by roughly 0.75 GB).

readonly MODEL_REPO="Code-Dev/nllb-200-distilled-1.3B-ct2-int8"
readonly MODEL_REPO_PATH="${MODEL_REPO}/resolve/main"
readonly MODEL_BASE="https://huggingface.co/${MODEL_REPO_PATH}"
# The SentencePiece tokenizer is identical across NLLB-200 releases; take it
# from the official Facebook repository.
readonly TOKENIZER_REPO_PATH="facebook/nllb-200-distilled-1.3B/resolve/main"
readonly TOKENIZER_BASE="https://huggingface.co/${TOKENIZER_REPO_PATH}"
readonly OUTPUT_DIR="${1:?output directory is required}"

readonly FILES=(
  model.bin
  shared_vocabulary.json
  sentencepiece.bpe.model
  config.json
)

# 供共享下载器使用的仓库相对路径。
repo_path_of() {
  case "$1" in
    sentencepiece.bpe.model)
      echo "${TOKENIZER_REPO_PATH}/$1"
      ;;
    *)
      echo "${MODEL_REPO_PATH}/$1"
      ;;
  esac
}

# SHA-256 of each file (the LFS oid exposed by the Hugging Face `x-linked-etag`).
sha256_of() {
  case "$1" in
    model.bin)
      echo "645d63967bee99a99dfffe78bd4ee1be80bd8adbe64624549774a81ccbad9ec2"
      ;;
    shared_vocabulary.json)
      echo "af53bfd0e6f726209e7325e45b87ab3b14e5856f7d42d7b9be91de3287c45267"
      ;;
    sentencepiece.bpe.model)
      echo "14bb8dfb35c0ffdea7bc01e56cea38b9e3d5efcdcb9c251d6b40538e1aab555a"
      ;;
    config.json)
      echo "8f6496adfc930cbfecbe8281112197705c488fab47d34b4829b06d7f478909af"
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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../common/hf_download.sh
source "${script_dir}/../common/hf_download.sh"

mkdir -p "$OUTPUT_DIR"
for file in "${FILES[@]}"; do
  # 通过共享下载器处理 Hugging Face 的 429 限流（重试 + 断点续传 + 镜像回退）。
  hf_download "$(repo_path_of "$file")" "$OUTPUT_DIR/$file"
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
Model: nllb-200-distilled-1.3B (CTranslate2 int8)
Source: https://huggingface.co/${MODEL_REPO}
Tokenizer: ${TOKENIZER_BASE}/sentencepiece.bpe.model
Original model: facebook/nllb-200-distilled-1.3B
License: CC-BY-NC 4.0 (non-commercial)
EOF
