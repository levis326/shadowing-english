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
  --onedir \
  --name pronunciation-server \
  --distpath "$OUTPUT_DIR" \
  --workpath "$work_dir/build" \
  --specpath "$work_dir" \
  --clean \
  --collect-all torchaudio \
  --collect-all soundfile \
  "$script_dir/pronunciation_server.py"

# 用 `--onedir` 而不是 `--onefile`：onefile 每次启动都会把自己解压到宿主机的
# `%TEMP%\_MEIxxxx`，在 U 盘上换电脑运行时会往别人的电脑里写文件；onedir 的
# 可执行文件与依赖都在程序目录内，启动也更快。
# PyInstaller 会把可执行文件放在 `$OUTPUT_DIR/pronunciation-server/` 里。
if [[ "$TARGET" == "windows-x64" ]]; then
  test -f "$OUTPUT_DIR/pronunciation-server/pronunciation-server.exe"
else
  test -x "$OUTPUT_DIR/pronunciation-server/pronunciation-server"
fi

cat > "$OUTPUT_DIR/BUILD-INFO.txt" <<EOF
pronunciation-server (PyInstaller, onedir)
Dependencies: torch + torchaudio (CPU) + soundfile (prebuilt wheels)
Target: ${TARGET}
EOF
chmod +x "$OUTPUT_DIR/pronunciation-server/pronunciation-server" 2>/dev/null || true
