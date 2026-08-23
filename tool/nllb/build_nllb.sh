#!/usr/bin/env bash
set -euo pipefail

# Builds the bundled `nllb-translate` binary: the custom CTranslate2 CLI
# (tool/nllb/nllb_translate.cpp) linked against a static CTranslate2 and a
# static sentencepiece.
#
# Usage: tool/nllb/build_nllb.sh <target> <output-dir>
#   target: linux-x64 | windows-x64 | macos-universal
#
# The binary is later bundled next to the app executable (see desktop_nllb.dart).

readonly CT2_VERSION="v4.8.1"
readonly SPM_VERSION="v0.2.2"
readonly TARGET="${1:?target is required}"
readonly OUTPUT_DIR="${2:?output directory is required}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

git clone --depth 1 --branch "$CT2_VERSION" --recursive \
  https://github.com/OpenNMT/CTranslate2.git "$work_dir/ctranslate2"
git clone --depth 1 --branch "$SPM_VERSION" \
  https://github.com/google/sentencepiece.git "$work_dir/sentencepiece"

cp "$script_dir/nllb_translate.cpp" "$work_dir/nllb_translate.cpp"

cat > "$work_dir/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.15)
project(nllb-translate LANGUAGES C CXX)

set(CMAKE_BUILD_TYPE Release)
set(BUILD_SHARED_LIBS OFF)

# CTranslate2: CPU-only, portable, no external runtime dependencies.
set(WITH_MKL OFF CACHE BOOL "" FORCE)
set(WITH_DNNL OFF CACHE BOOL "" FORCE)
set(WITH_OPENBLAS OFF CACHE BOOL "" FORCE)
set(WITH_RUY OFF CACHE BOOL "" FORCE)
set(WITH_ACCELERATE OFF CACHE BOOL "" FORCE)
set(WITH_CUDA OFF CACHE BOOL "" FORCE)
set(WITH_CUDNN OFF CACHE BOOL "" FORCE)
set(BUILD_CLI OFF CACHE BOOL "" FORCE)
set(BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(OPENMP_RUNTIME "NONE" CACHE STRING "" FORCE)
set(ENABLE_CPU_DISPATCH ON CACHE BOOL "" FORCE)
add_subdirectory(ctranslate2)

# sentencepiece: static, no tcmalloc, no shared library.
set(SPM_ENABLE_SHARED OFF CACHE BOOL "" FORCE)
set(SPM_ENABLE_TCMALLOC OFF CACHE BOOL "" FORCE)
set(SPM_BUILD_TEST OFF CACHE BOOL "" FORCE)
set(SPM_ENABLE_BENCHMARK OFF CACHE BOOL "" FORCE)
add_subdirectory(sentencepiece)

add_executable(nllb-translate nllb_translate.cpp)
set_target_properties(nllb-translate PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED ON
)
target_link_libraries(nllb-translate PRIVATE ctranslate2 sentencepiece-static)
EOF

mkdir -p "$OUTPUT_DIR"
cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

build_one() {
  local build_dir="$1"
  shift
  cmake -S "$work_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release "$@"
  cmake --build "$build_dir" --config Release --target nllb-translate -j"$cpu_count"
}

case "$TARGET" in
  linux-x64)
    build_one "$work_dir/build"
    cp "$work_dir/build/nllb-translate" "$OUTPUT_DIR/nllb-translate"
    ;;
  windows-x64)
    build_one "$work_dir/build"
    cp "$work_dir/build/Release/nllb-translate.exe" "$OUTPUT_DIR/nllb-translate.exe"
    ;;
  macos-universal)
    build_one "$work_dir/build-arm64" -DCMAKE_OSX_ARCHITECTURES=arm64
    build_one "$work_dir/build-x64" -DCMAKE_OSX_ARCHITECTURES=x86_64
    lipo -create \
      "$work_dir/build-arm64/nllb-translate" \
      "$work_dir/build-x64/nllb-translate" \
      -output "$OUTPUT_DIR/nllb-translate"
    ;;
  *)
    echo "Unsupported nllb target: $TARGET" >&2
    exit 1
    ;;
esac

cp "$work_dir/ctranslate2/LICENSE" "$OUTPUT_DIR/CTRANSLATE2-LICENSE.txt"
cp "$work_dir/sentencepiece/LICENSE" "$OUTPUT_DIR/SENTENCEPIECE-LICENSE.txt"
cat > "$OUTPUT_DIR/BUILD-INFO.txt" <<EOF
CTranslate2 ${CT2_VERSION}
sentencepiece ${SPM_VERSION}
Target: ${TARGET}
EOF
chmod +x "$OUTPUT_DIR/nllb-translate" 2>/dev/null || true
