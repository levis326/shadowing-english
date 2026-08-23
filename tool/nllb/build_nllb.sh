#!/usr/bin/env bash
set -euo pipefail

# Builds the bundled `nllb-translate` binary: the custom CTranslate2 CLI
# (tool/nllb/nllb_translate.cpp) linked against static CTranslate2, oneDNN
# (the CPU GEMM backend CTranslate2 requires) and static sentencepiece.
#
# Usage: tool/nllb/build_nllb.sh <target> <output-dir>
#   target: linux-x64 | windows-x64 | macos-universal
#
# The binary is later bundled next to the app executable (see desktop_nllb.dart).

readonly CT2_VERSION="v4.8.1"
readonly SPM_VERSION="v0.2.2"
readonly DNNL_VERSION="v3.13.1"
readonly TARGET="${1:?target is required}"
readonly OUTPUT_DIR="${2:?output directory is required}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

git clone --depth 1 --branch "$CT2_VERSION" \
  https://github.com/OpenNMT/CTranslate2.git "$work_dir/ctranslate2"
# Only fetch the submodules a CPU-only build references (spdlog + cpu_features).
# cutlass/thrust/googletest/cxxopts are CUDA/test/CLI-only and are skipped to
# keep the clone fast and lean.
git -C "$work_dir/ctranslate2" submodule update --init --depth 1 \
  third_party/spdlog third_party/cpu_features
git clone --depth 1 --branch "$SPM_VERSION" \
  https://github.com/google/sentencepiece.git "$work_dir/sentencepiece"
git clone --depth 1 --branch "$DNNL_VERSION" \
  https://github.com/oneapi-src/oneDNN.git "$work_dir/oneDNN"

cp "$script_dir/nllb_translate.cpp" "$work_dir/nllb_translate.cpp"

mkdir -p "$OUTPUT_DIR"
cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)"

# Build and install oneDNN (static, compiler OpenMP for parallel GEMMs).
cmake -S "$work_dir/oneDNN" -B "$work_dir/dnnl-build" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DDNNL_BUILD_TESTS=OFF \
  -DDNNL_BUILD_EXAMPLES=OFF \
  -DDNNL_LIBRARY_TYPE=STATIC \
  -DDNNL_CPU_RUNTIME=OMP \
  -DCMAKE_INSTALL_PREFIX="$work_dir/dnnl-install"
cmake --build "$work_dir/dnnl-build" --config Release -j"$cpu_count"
cmake --install "$work_dir/dnnl-build" --config Release

dnnl_include="$work_dir/dnnl-install/include"
if [[ "$TARGET" == "windows-x64" ]]; then
  dnnl_lib="$work_dir/dnnl-install/lib/dnnl.lib"
else
  dnnl_lib="$work_dir/dnnl-install/lib/libdnnl.a"
fi

cat > "$work_dir/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.15)
project(nllb-translate LANGUAGES C CXX)

set(CMAKE_BUILD_TYPE Release)
set(BUILD_SHARED_LIBS OFF)

# CTranslate2: CPU-only, oneDNN GEMM backend, compiler OpenMP for threading.
set(WITH_MKL OFF CACHE BOOL "" FORCE)
set(WITH_DNNL ON CACHE BOOL "" FORCE)
set(WITH_OPENBLAS OFF CACHE BOOL "" FORCE)
set(WITH_RUY OFF CACHE BOOL "" FORCE)
set(WITH_ACCELERATE OFF CACHE BOOL "" FORCE)
set(WITH_CUDA OFF CACHE BOOL "" FORCE)
set(WITH_CUDNN OFF CACHE BOOL "" FORCE)
set(BUILD_CLI OFF CACHE BOOL "" FORCE)
set(BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(OPENMP_RUNTIME "COMP" CACHE STRING "" FORCE)
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
# sentencepiece v0.2.2 does not export its include dirs as a PUBLIC interface.
# Add them explicitly: src/ for sentencepiece_processor.h, and the top dir for
# the `third_party/absl/...` headers that sentencepiece_processor.h includes.
target_include_directories(nllb-translate PRIVATE
  sentencepiece/src
  sentencepiece)
target_link_libraries(nllb-translate PRIVATE ctranslate2 sentencepiece-static)
EOF

build_one() {
  local build_dir="$1"
  shift
  # CMake 4.x rejects subprojects declaring cmake_minimum_required < 3.5
  # (protobuf/abseil pulled in by sentencepiece); keep those configuring.
  cmake -S "$work_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DDNNL_INCLUDE_DIR="$dnnl_include" \
    -DDNNL_LIBRARY="$dnnl_lib" \
    "$@"
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
oneDNN ${DNNL_VERSION}
Target: ${TARGET}
EOF
chmod +x "$OUTPUT_DIR/nllb-translate" 2>/dev/null || true
