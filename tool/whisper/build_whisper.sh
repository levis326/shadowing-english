#!/usr/bin/env bash
set -euo pipefail

# Builds a minimal whisper.cpp `whisper-server` binary for the given target.
#
# Usage: tool/whisper/build_whisper.sh <target> <output-dir>
#   target: linux-x64 | windows-x64 | macos-universal
#
# The binary is later bundled next to the app executable (see desktop_whisper.dart).

readonly WHISPER_VERSION="v1.7.5"
readonly TARGET="${1:?target is required}"
readonly OUTPUT_DIR="${2:?output directory is required}"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

archive="$work_dir/whisper.tar.gz"
curl --fail --location --retry 3 \
  "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/${WHISPER_VERSION}.tar.gz" \
  --output "$archive"
tar -xzf "$archive" -C "$work_dir"
source_dir="$work_dir/whisper.cpp-${WHISPER_VERSION#v}"

mkdir -p "$OUTPUT_DIR"

common_flags=(
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
  -DWHISPER_BUILD_EXAMPLES=ON
  -DWHISPER_BUILD_TESTS=OFF
  # Portable binary: no -march=native, no OpenMP runtime dependency
  # (vcomp140.dll on Windows / libomp on macOS).
  -DGGML_NATIVE=OFF
  -DGGML_OPENMP=OFF
)

build_one() {
  local target="$1"
  local build_dir="$2"
  local extra_flags=()

  case "$target" in
    linux-x64)
      ;;
    windows-x64)
      ;;
    macos-arm64)
      extra_flags+=(-DCMAKE_OSX_ARCHITECTURES=arm64)
      ;;
    macos-x64)
      extra_flags+=(-DCMAKE_OSX_ARCHITECTURES=x86_64)
      ;;
    *)
      echo "Unsupported whisper target: $target" >&2
      exit 1
      ;;
  esac

  cmake -S "$source_dir" -B "$build_dir" "${common_flags[@]}" "${extra_flags[@]}"
  cmake --build "$build_dir" --config Release -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)"
}

case "$TARGET" in
  linux-x64)
    build_one linux-x64 "$work_dir/build"
    cp "$work_dir/build/bin/whisper-server" "$OUTPUT_DIR/whisper-server"
    ;;
  windows-x64)
    build_one windows-x64 "$work_dir/build"
    cp "$work_dir/build/bin/Release/whisper-server.exe" "$OUTPUT_DIR/whisper-server.exe"
    ;;
  macos-universal)
    build_one macos-arm64 "$work_dir/build-arm64"
    build_one macos-x64 "$work_dir/build-x64"
    lipo -create \
      "$work_dir/build-arm64/bin/whisper-server" \
      "$work_dir/build-x64/bin/whisper-server" \
      -output "$OUTPUT_DIR/whisper-server"
    ;;
  *)
    echo "Unsupported whisper target: $TARGET" >&2
    exit 1
    ;;
esac

cp "$source_dir/LICENSE" "$OUTPUT_DIR/WHISPER-LICENSE.txt"
cat > "$OUTPUT_DIR/BUILD-INFO.txt" <<EOF
whisper.cpp ${WHISPER_VERSION}
Source: https://github.com/ggml-org/whisper.cpp
Target: ${TARGET}
EOF
chmod +x "$OUTPUT_DIR/whisper-server" 2>/dev/null || true
