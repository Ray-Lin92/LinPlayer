package com.example.linplayer_mobile

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var exoPlayerPlugin: ExoPlayerPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 注册 ExoPlayer 插件（v2 - 支持字幕轨道、ffmpeg 扩展）
        exoPlayerPlugin = ExoPlayerPlugin(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
            flutterEngine.renderer
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.linplayer/exoplayer")
            .setMethodCallHandler(exoPlayerPlugin)

        // 注意：MPV 内核已迁移到 media_kit（Dart 封装库），
        // 不再使用 FFI 直调 libmpv.so，因此不再注册 MpvTexturePlugin。
        // libass 也已通过 ExoPlayer 原生字幕管线和 media_kit 内置支持，
        // 不再使用自定义 libass JNI。
    }

    override fun onDestroy() {
        exoPlayerPlugin?.disposeAll()
        super.onDestroy()
    }
}

object LibassBridge {
    private var assLibrary: Long = 0
    private var assRenderer: Long = 0
    private var assTrack: Long = 0
    private var initialized = false

    init {
        System.loadLibrary("ass")
        System.loadLibrary("linass_jni")
    }

    external fun nativeIsAvailable(): Boolean
    external fun nativeInit(width: Int, height: Int): Long
    external fun nativeLoadFile(assLibrary: Long, path: String): Long
    external fun nativeLoadMemory(assLibrary: Long, data: ByteArray, codec: String): Long
    external fun nativeSetFontSize(renderer: Long, size: Int)
    external fun nativeSetFontName(renderer: Long, name: String)
    external fun nativeRenderFrame(renderer: Long, track: Long, ptsMs: Long): ByteArray?
    external fun nativeDispose(assLibrary: Long, renderer: Long, track: Long)

    fun isAvailable(context: Context): Boolean {
        return try {
            nativeIsAvailable()
        } catch (e: UnsatisfiedLinkError) {
            false
        }
    }

    fun init(context: Context, width: Int, height: Int) {
        if (initialized) dispose()
        assLibrary = nativeInit(width, height)
        assRenderer = assLibrary
        initialized = true
    }

    fun loadSubFile(path: String) {
        if (assLibrary == 0L) return
        assTrack = nativeLoadFile(assLibrary, path)
    }

    fun loadSubMemory(data: ByteArray, codec: String) {
        if (assLibrary == 0L) return
        assTrack = nativeLoadMemory(assLibrary, data, codec)
    }

    fun setFontSize(size: Int) {
        if (assRenderer == 0L) return
        nativeSetFontSize(assRenderer, size)
    }

    fun setFontName(name: String) {
        if (assRenderer == 0L) return
        nativeSetFontName(assRenderer, name)
    }

    fun renderFrame(ptsMs: Long, changed: IntArray): ByteArray? {
        if (assRenderer == 0L || assTrack == 0L) return null
        return nativeRenderFrame(assRenderer, assTrack, ptsMs)
    }

    fun dispose() {
        if (!initialized) return
        nativeDispose(assLibrary, assRenderer, assTrack)
        assLibrary = 0
        assRenderer = 0
        assTrack = 0
        initialized = false
    }
}
