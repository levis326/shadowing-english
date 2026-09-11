#!/usr/bin/env bash
# Shared resilient downloader for Hugging Face model files.
#
# Usage:
#   source tool/common/hf_download.sh
#   hf_download "<repo>/resolve/main/<file>" "<output-file>"
#
# Why: GitHub runners download anonymously and Hugging Face answers HTTP 429
# (Too Many Requests) when the shared runner IP is throttled. This helper
# mitigates that with:
#   * optional authentication via HF_TOKEN (set the repo secret to avoid
#     anonymous rate limits entirely);
#   * resumable transfers (`--continue-at -`), so a throttled 1.3 GB download
#     continues instead of restarting;
#   * several retries with increasing backoff;
#   * automatic fallback to a mirror endpoint.
#
# Environment:
#   HF_TOKEN             optional Hugging Face access token
#   HF_ENDPOINT          primary endpoint  (default https://huggingface.co)
#   HF_MIRROR_ENDPOINT   fallback endpoint (default https://hf-mirror.com)

HF_ENDPOINT="${HF_ENDPOINT:-https://huggingface.co}"
HF_MIRROR_ENDPOINT="${HF_MIRROR_ENDPOINT:-https://hf-mirror.com}"

hf_download() {
  local relative_path="${1:?relative path is required}"
  local output_file="${2:?output file is required}"
  local -a endpoints=("${HF_ENDPOINT}")
  if [[ -n "${HF_MIRROR_ENDPOINT}" && "${HF_MIRROR_ENDPOINT}" != "${HF_ENDPOINT}" ]]; then
    endpoints+=("${HF_MIRROR_ENDPOINT}")
  fi
  local -a auth=()
  if [[ -n "${HF_TOKEN:-}" ]]; then
    auth=(-H "Authorization: Bearer ${HF_TOKEN}")
  fi

  local endpoint url attempt delay
  for endpoint in "${endpoints[@]}"; do
    url="${endpoint}/${relative_path}"
    for attempt in 1 2 3 4 5; do
      echo "Downloading ${url} (attempt ${attempt})"
      if curl --fail --location --continue-at - \
        --retry 3 --retry-delay 5 --retry-all-errors \
        --connect-timeout 30 \
        "${auth[@]}" "$url" --output "$output_file"; then
        return 0
      fi
      delay=$((attempt * 15))
      echo "Download attempt failed; retrying in ${delay}s" >&2
      sleep "$delay"
    done
    echo "Endpoint ${endpoint} exhausted for ${relative_path}" >&2
  done

  echo "Failed to download ${relative_path}" >&2
  return 1
}
