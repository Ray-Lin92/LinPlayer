#!/bin/bash
# FFmpeg Android 编译脚本
# 用于编译 ExoPlayer 的 ffmpeg 扩展

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEDIA_ROOT="$SCRIPT_DIR/media"
FFMPEG_DIR="$MEDIA_ROOT/libraries/decoder_ffmpeg/src/main/jni/ffmpeg"
NDK_PATH="${NDK_PATH:-/opt/android-ndk}"

# 支持的架构
ARCHS=("arm64-v8a" "armeabi-v7a" "x86_64")

# 启用字幕解码器
ENABLED_DECODERS=(
    pgssub      # PGS 字幕
    dvbsub      # DVB 字幕
    dvdsub      # DVD 字幕
    ass         # ASS 字幕渲染辅助
    ssa
    srt
    webvtt
)

echo "=========================================="
echo "ExoPlayer FFmpeg Extension Builder"
echo "=========================================="
echo "NDK: $NDK_PATH"
echo "Media3 Root: $MEDIA_ROOT"
echo ""

# 检查 NDK
if [ ! -d "$NDK_PATH" ]; then
    echo "错误: NDK 未找到: $NDK_PATH"
    echo "请设置环境变量: export NDK_PATH=/path/to/ndk"
    exit 1
fi

# 编译 FFmpeg 库
cd "$FFMPEG_DIR"

for ARCH in "${ARCHS[@]}"; do
    echo "编译架构: $ARCH"
    
    case $ARCH in
        arm64-v8a)
            CPU=armv8-a
            CROSS_PREFIX=aarch64-linux-android21-
            ;;
        armeabi-v7a)
            CPU=armv7-a
            CROSS_PREFIX=arm-linux-androideabi21-
            ;;
        x86_64)
            CPU=x86-64
            CROSS_PREFIX=x86_64-linux-android21-
            ;;
    esac
    
    TOOLCHAIN=$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64
    
    ./configure \
        --target-os=android \
        --arch=$ARCH \
        --cpu=$CPU \
        --cross-prefix=$TOOLCHAIN/bin/$CROSS_PREFIX \
        --cc=$TOOLCHAIN/bin/${CROSS_PREFIX}clang \
        --cxx=$TOOLCHAIN/bin/${CROSS_PREFIX}clang++ \
        --prefix=$MEDIA_ROOT/libraries/decoder_ffmpeg/src/main/jni/ffmpeg/build/$ARCH \
        --enable-static \
        --disable-shared \
        --disable-doc \
        --disable-ffmpeg \
        --disable-ffplay \
        --disable-ffprobe \
        --disable-network \
        --enable-decoder=$(IFS=,; echo "${ENABLED_DECODERS[*]}") \
        --disable-everything \
        --disable-avdevice \
        --disable-avformat \
        --disable-swresample \
        --disable-postproc \
        --disable-avfilter \
        --disable-symver \
        --extra-cflags="-O3 -fPIC" \
        --extra-ldflags="-Wl,--no-undefined -Wl,-z,noexecstack"
    
    make -j$(nproc)
    make install
    make clean
    
    echo "架构 $ARCH 编译完成"
done

# 构建 AAR
cd "$MEDIA_ROOT"
./gradlew :libraries:decoder_ffmpeg:assembleRelease

echo ""
echo "=========================================="
echo "编译完成!"
echo "AAR 文件: libraries/decoder_ffmpeg/build/outputs/aar/decoder_ffmpeg-release.aar"
echo "=========================================="
