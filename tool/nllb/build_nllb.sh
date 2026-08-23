#!/usr/bin/env bash
set -euo pipefail

# Packages the local NLLB translation server (tool/nllb/nllb_server.py) into a
# self-contained binary using PyInstaller and the prebuilt `ctranslate2` +
# `sentencepiece` wheels. Nothing is compiled from source, which avoids the MSVC
# CRT / OpenMP / link-order problems of building CTranslate2 from source.
#
# Usage: tool/nllb/build_nllb.sh <target> <output-dir>
#   target: linux-x64 | windows-x64 | macos-universal
#
# Requires a Python with network access for `pip install`. The resulting binary
# is later bundled next to the app executable (see desktop_nllb.dart).

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

"$PYTHON" -m pip install --quiet --disable-pip-version-check \
  ctranslate2 sentencepiece pyinstaller

"$PYTHON" -m PyInstaller \
  --onefile \
  --name nllb-server \
  --distpath "$OUTPUT_DIR" \
  --workpath "$work_dir/build" \
  --specpath "$work_dir" \
  --clean \
  "$script_dir/nllb_server.py"

if [[ "$TARGET" == "windows-x64" ]]; then
  test -f "$OUTPUT_DIR/nllb-server.exe"
else
  test -x "$OUTPUT_DIR/nllb-server"
fi

cat > "$OUTPUT_DIR/BUILD-INFO.txt" <<EOF
nllb-server (PyInstaller)
Dependencies: ctranslate2 + sentencepiece (prebuilt wheels)
Target: ${TARGET}
EOF
chmod +x "$OUTPUT_DIR/nllb-server" 2>/dev/null || true
