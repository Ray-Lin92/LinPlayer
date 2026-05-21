# ExoPlayer FFmpeg 扩展编译指南

## 概述

ExoPlayer 的 `media3-decoder-ffmpeg` 扩展提供了 ffmpeg 软解支持，包括对 PGS/SUP 图形字幕的解码能力。

**注意**：Google **不提供**此扩展的预编译版本，需要自行编译。

## 方案选择

### 方案 A：GitHub Actions 自动编译（最推荐 ⭐）

LinPlayer 已配置好 GitHub Actions，**每次 Push 到 main 分支时自动编译** ffmpeg 扩展。

#### 使用方法

1. **Fork 本仓库**（如果还没做）

2. **启用 GitHub Actions**
   - 进入仓库 Settings -> Actions -> General
   - 确保 Actions 权限已启用

3. **自动触发**
   - Push 代码到 `main`/`master` 分支时自动触发
   - 也可以手动触发：Actions -> Build Flutter APK -> Run workflow
   - 勾选 **"Include FFmpeg extension"**

4. **等待编译完成**
   - 首次编译约 15-25 分钟（需要下载 NDK、ExoPlayer 源码、FFmpeg 源码并编译）
   - 后续编译会利用缓存，约 2-5 分钟

5. **下载 APK**
   - Actions -> 最新的 workflow run -> Artifacts
   - 下载 `debug-apk` 或 `release-apk`

#### 缓存机制

GitHub Actions 会自动缓存编译好的 ffmpeg AAR 文件：
- 缓存 Key: `ffmpeg-aar-{exoPlayer版本}-{ffmpeg版本}-{exoplayer-ffmpeg目录hash}`
- 只要 `android/exoplayer-ffmpeg/` 目录不变，就会复用缓存
- 缓存有效期：90 天

#### 单独编译 FFmpeg 扩展

如果只需要 AAR 文件（不构建 APK）：
1. Actions -> Build FFmpeg Extension -> Run workflow
2. 编译完成后下载 `ffmpeg-extension-all` artifact
3. 解压后将 `.aar` 文件放入 `android/exoplayer-ffmpeg/libs/`

### 方案 B：自行编译 ffmpeg 扩展（适合本地开发）

适用于需要完整 PGS/SUP 支持的场景。

#### 前置要求

- Linux 或 macOS（Windows 需使用 WSL2）
- Android NDK（r25c 或更新版本）
- Git
- 约 2GB 磁盘空间

#### 编译步骤

1. **克隆 ExoPlayer 源码**
   ```bash
   git clone https://github.com/androidx/media.git
   cd media
   git checkout 1.3.1
   ```

2. **初始化 ffmpeg 子模块**
   ```bash
   cd libraries/decoder_ffmpeg/src/main/jni
   git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg
   cd ffmpeg
   git checkout n6.0  # 或最新稳定版
   ```

3. **编译 ffmpeg 库**
   ```bash
   cd ../..  # 回到 jni 目录
   export NDK_PATH=/path/to/your/android-ndk
   ./build_ffmpeg.sh \
     --ndk-path $NDK_PATH \
     --arch arm64-v8a \
     --enable-decoder=pgssub \
     --enable-decoder=dvbsub \
     --enable-decoder=dvdsub
   ```

4. **编译 AAR 包**
   ```bash
   cd ../../../../..  # 回到 media 根目录
   ./gradlew :libraries:decoder_ffmpeg:assembleRelease
   ```

5. **复制到项目**
   ```bash
   cp libraries/decoder_ffmpeg/build/outputs/aar/decoder_ffmpeg-release.aar \
      /path/to/LinPlayer/android/exoplayer-ffmpeg/libs/
   ```

6. **修改项目 build.gradle.kts**
   
   在 `android/app/build.gradle.kts` 中添加：
   ```kotlin
   dependencies {
       implementation(files("../exoplayer-ffmpeg/libs/decoder_ffmpeg-release.aar"))
       // ... 其他依赖
   }
   ```

### 方案 C：使用 Docker 编译（适合本地开发）

如果你不想配置环境，可以使用提供的 Docker 脚本：

```bash
cd android/exoplayer-ffmpeg
docker build -t exoplayer-ffmpeg .
docker run --rm -v $(pwd)/output:/output exoplayer-ffmpeg
```

### 方案 D：PGS/SUP Fallback（最实际）

如果不需要自行编译，LinPlayer 提供了自动 fallback 机制：

- **检测到 PGS/SUP 字幕时**：自动提示用户切换到 **MPV 内核**
- **MPV 内核**：基于 libmpv，原生支持 PGS/SUP 等所有字幕格式

## 在 LinPlayer 中启用 FFmpeg 扩展

### 1. 添加 AAR 文件

将编译好的 `decoder_ffmpeg-release.aar` 放入：
```
android/exoplayer-ffmpeg/libs/
```

### 2. 修改 app/build.gradle.kts

```kotlin
dependencies {
    implementation("androidx.media3:media3-exoplayer:1.3.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.3.1")
    implementation("androidx.media3:media3-exoplayer-dash:1.3.1")
    
    // FFmpeg 扩展（本地 AAR）
    implementation(files("../exoplayer-ffmpeg/libs/decoder_ffmpeg-release.aar"))
}
```

### 3. 启用扩展渲染器

`ExoPlayerPlugin.kt` 中已经配置好了：
```kotlin
val renderersFactory = DefaultRenderersFactory(context)
    .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)

val exoPlayer = ExoPlayer.Builder(context)
    .setRenderersFactory(renderersFactory)
    .build()
```

## 验证是否生效

在 Logcat 中查看以下日志：
```
Loaded FfmpegAudioRenderer.
Loaded FfmpegVideoRenderer.
```

如果出现，说明 ffmpeg 扩展已成功加载。

## 常见问题

### Q: GitHub Actions 编译失败怎么办？
A: 
1. 检查 Actions 日志，看是哪个步骤失败
2. 常见原因：
   - NDK 下载失败（网络问题）：重试即可
   - FFmpeg 配置错误：检查 `build_ffmpeg_android.sh` 脚本
   - 内存不足：GitHub Actions 提供 7GB 内存，通常够用
3. 如果一直失败，可以使用方案 D（切换到 MPV 内核）

### Q: GitHub Actions 编译时间太长？
A:
- 首次编译需要 15-25 分钟（下载 + 编译）
- 后续编译利用缓存，只需 2-5 分钟
- 如果只修改了 Dart 代码，没有改动 `android/exoplayer-ffmpeg/`，缓存会完全命中

### Q: 可以在本地编译吗？
A: 可以。本地编译步骤见方案 B。
- Linux/macOS：直接运行脚本
- Windows：建议使用 WSL2 或 Docker

### Q: Windows 上能编译吗？
A: 官方脚本不支持原生 Windows。建议使用：
- WSL2（推荐）
- Docker
- GitHub Actions（最省事）

### Q: APK 会增加多大？
A: 约 5-15MB（取决于编译的架构和启用的解码器）。

### Q: 必须编译 ffmpeg 扩展吗？
A: **不是必须的**。对于 PGS/SUP 字幕，LinPlayer 会自动提示切换到 **MPV 内核**，它原生支持所有字幕格式。

### Q: 如何验证 ffmpeg 扩展是否生效？
A: 在 Logcat 中查看：
```
Loaded FfmpegAudioRenderer.
Loaded FfmpegVideoRenderer.
```
或者查看 Gradle 构建日志：
```
✅ FFmpeg extension found: .../ffmpeg-extension.aar
```

## 参考

- [ExoPlayer FFmpeg Extension 官方文档](https://developer.android.com/media/media3/exoplayer/extensions/ffmpeg)
- [FFmpeg 编译指南](https://trac.ffmpeg.org/wiki/CompilationGuide/Android)
