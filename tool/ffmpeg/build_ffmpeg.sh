#!/usr/bin/env bash
set -euo pipefail

readonly FFMPEG_VERSION="8.1.2"
readonly FFMPEG_SHA256="464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c"
readonly TARGET="${1:?target is required}"
readonly OUTPUT_DIR="${2:?output directory is required}"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

archive="$work_dir/ffmpeg.tar.xz"
curl --fail --location --retry 3 \
  "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" \
  --output "$archive"

if command -v sha256sum >/dev/null 2>&1; then
  actual_sha="$(sha256sum "$archive" | awk '{print $1}')"
else
  actual_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
fi
if [[ "$actual_sha" != "$FFMPEG_SHA256" ]]; then
  echo "FFmpeg source checksum mismatch" >&2
  exit 1
fi

tar -xf "$archive" -C "$work_dir"
source_dir="$work_dir/ffmpeg-${FFMPEG_VERSION}"

common_flags=(
  --disable-autodetect
  --disable-debug
  --disable-doc
  --disable-everything
  --disable-network
  --disable-programs
  --enable-ffmpeg
  --enable-avcodec
  --enable-avfilter
  --enable-avformat
  --enable-swresample
  --enable-protocol=file,pipe
  --enable-demuxer=aac,ac3,aiff,asf,avi,flac,flv,matroska,mov,mp3,mpegps,mpegts,ogg,srt,wav
  --enable-decoder=aac,aac_latm,ac3,eac3,alac,flac,mp3,opus,vorbis,wmav1,wmav2,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_s32be,pcm_f32le,pcm_f64le,ass,ssa,movtext,subrip,webvtt
  --enable-encoder=aac,movtext,pcm_s16le,srt
  --enable-parser=aac,aac_latm,ac3,flac,mpegaudio,opus,vorbis
  --enable-muxer=ipod,segment,srt,wav
  --enable-filter=aformat,aresample,anull,sine
  --enable-indev=lavfi
  --enable-small
)

build_one() {
  local target="$1"
  local target_dir="$2"
  local extra_flags=()

  case "$target" in
    linux-x64)
      extra_flags+=(--target-os=linux --arch=x86_64 --extra-ldflags=-static)
      ;;
    windows-x64)
      extra_flags+=(--target-os=mingw32 --arch=x86_64)
      ;;
    macos-arm64)
      extra_flags+=(
        --target-os=darwin
        --arch=arm64
        --cc=clang
        --host-cc=clang
        --extra-cflags=-arch\ arm64
        --extra-ldflags=-arch\ arm64
      )
      if [[ "$(uname -m)" != "arm64" ]]; then
        extra_flags+=(--enable-cross-compile)
      fi
      ;;
    macos-x64)
      extra_flags+=(
        --target-os=darwin
        --arch=x86_64
        --disable-x86asm
        --cc=clang
        --host-cc=clang
        --extra-cflags=-arch\ x86_64
        --extra-ldflags=-arch\ x86_64
      )
      if [[ "$(uname -m)" != "x86_64" ]]; then
        extra_flags+=(--enable-cross-compile)
      fi
      ;;
    *)
      echo "Unsupported FFmpeg target: $target" >&2
      exit 1
      ;;
  esac

  mkdir -p "$target_dir"
  pushd "$target_dir" >/dev/null
  "$source_dir/configure" "${common_flags[@]}" "${extra_flags[@]}"
  make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)"
  popd >/dev/null
}

mkdir -p "$OUTPUT_DIR"
if [[ "$TARGET" == "macos-universal" ]]; then
  build_one macos-arm64 "$work_dir/build-arm64"
  build_one macos-x64 "$work_dir/build-x64"
  lipo -create \
    "$work_dir/build-arm64/ffmpeg" \
    "$work_dir/build-x64/ffmpeg" \
    -output "$OUTPUT_DIR/ffmpeg"
else
  build_one "$TARGET" "$work_dir/build"
  binary_name="ffmpeg"
  if [[ "$TARGET" == "windows-x64" ]]; then
    binary_name="ffmpeg.exe"
  fi
  cp "$work_dir/build/$binary_name" "$OUTPUT_DIR/$binary_name"
fi

cp "$source_dir/COPYING.LGPLv2.1" "$OUTPUT_DIR/FFMPEG-LICENSE.txt"
cat > "$OUTPUT_DIR/BUILD-INFO.txt" <<EOF
FFmpeg ${FFMPEG_VERSION}
Source: https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz
Source SHA-256: ${FFMPEG_SHA256}
Target: ${TARGET}
Configuration: ${common_flags[*]}
EOF
chmod +x "$OUTPUT_DIR/ffmpeg" 2>/dev/null || true
