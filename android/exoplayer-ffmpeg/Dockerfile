FROM ubuntu:22.04

# 安装依赖
RUN apt-get update && apt-get install -y \
    git \
    wget \
    unzip \
    python3 \
    cmake \
    ninja-build \
    openjdk-17-jdk \
    && rm -rf /var/lib/apt/lists/*

# 下载 Android NDK
ENV NDK_VERSION=r25c
ENV NDK_PATH=/opt/android-ndk
RUN wget -q https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip -O /tmp/ndk.zip \
    && unzip -q /tmp/ndk.zip -d /opt \
    && mv /opt/android-ndk-${NDK_VERSION} ${NDK_PATH} \
    && rm /tmp/ndk.zip

# 下载 ExoPlayer 源码
WORKDIR /src
RUN git clone https://github.com/androidx/media.git \
    && cd media \
    && git checkout 1.3.1

# 下载 FFmpeg
WORKDIR /src/media/libraries/decoder_ffmpeg/src/main/jni
RUN git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg \
    && cd ffmpeg \
    && git checkout n6.0

# 编译脚本
COPY build_ffmpeg_android.sh /src/build_ffmpeg_android.sh
RUN chmod +x /src/build_ffmpeg_android.sh

# 编译并输出
WORKDIR /src/media
RUN /src/build_ffmpeg_android.sh

RUN ./gradlew :libraries:decoder_ffmpeg:assembleRelease

# 复制输出
RUN mkdir -p /output \
    && cp libraries/decoder_ffmpeg/build/outputs/aar/decoder_ffmpeg-release.aar /output/

CMD ["cp", "/output/decoder_ffmpeg-release.aar", "/output/"]
