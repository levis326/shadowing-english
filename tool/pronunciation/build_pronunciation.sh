#!/usr/bin/env bash
set -euo pipefail

# Packages the local pronunciation server (tool/pronunciation/pronunciation_server.py)
# into a self-contained binary using PyInstaller and the prebuilt CPU PyTorch /
# TorchAudio / soundfile wheels. Nothing is compiled from source.
#
# Usage: tool/pronunciation/build_pronunciation.sh <target> <output-dir>
#   target: linux-x64 | windows-x64 | macos-universal
#
# Requires a Python with network access for `pip install`. The resulting binary
# is later bundled next to the app executable.

readonly TARGET="${1:?target is required}"
readonly OUTPUT_DIR="${2:?output directory is required}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

if [[ "$TARGET" == "windows-x64" ]]; then
  PYTHON="${PYTHON:-python}"
else
  PYTHON="${PYTHON:-python3}"
fi

mkdir -p "$OUTPUT_DIR"

# CPU-only PyTorch first (smaller, no CUDA), then the rest from PyPI.
"$PYTHON" -m pip install --quiet --disable-pip-version-check \
  torch torchaudio --index-url https://download.pytorch.org/whl/cpu
"$PYTHON" -m pip install --quiet --disable-pip-version-check \
  soundfile pyinstaller

"$PYTHON" -m PyInstaller \
  --onefile \
  --name pronunciation-server \
  --distpath "$OUTPUT_DIR" \
  --workpath "$work_dir/build" \
  --specpath "$work_dir" \
  --clean \
  --collect-all torchaudio \
  --collect-all soundfile \
  "$script_dir/pronunciation_server.py"

if [[ "$TARGET" == "windows-x64" ]]; then
  test -f "$OUTPUT_DIR/pronunciation-server.exe"
else
  test -x "$OUTPUT_DIR/pronunciation-server"
fi

cat > "$OUTPUT_DIR/BUILD-INFO.txt" <<EOF
pronunciation-server (PyInstaller)
Dependencies: torch + torchaudio (CPU) + soundfile (prebuilt wheels)
Target: ${TARGET}
EOF
chmod +x "$OUTPUT_DIR/pronunciation-server" 2>/dev/null || true
