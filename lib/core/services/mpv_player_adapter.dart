import 'dart:async';
import 'dart:math' show max, min;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'player_adapter.dart';
import 'app_logger.dart';
import 'mpv_config_manager.dart';
import 'subtitle_processor.dart';

/// MPV 播放器适配器（v2.1 - media_kit + 高级功能）
///
/// 基于 media_kit，通过以下方式实现高级功能：
/// - 配置文件：字幕字体、大小、位置、音频/字幕延迟、画面比例、Anime4K
/// - Dart 层处理：运行时字幕时间轴偏移、ASS 样式修改
class MpvPlayerAdapter implements PlayerAdapter {
  static final _logger = AppLogger();
  static final _configManager = MpvConfigManager();

  Player? _player;
  VideoController? _videoController;

  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isCompleted = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;
  double _volume = 1.0;
  String? _errorMessage;

  // 当前配置值（用于运行时下发生效）
  double _subtitleDelay = 0.0;
  double _audioDelay = 0.0;
  double _subtitleScale = 1.0;
  double _subtitlePosition = 100.0;
  String? _subtitleFont;
  String? _aspectRatio;
  List<String>? _glslShaders;

  // 已处理字幕文件路径（用于切换字幕时重新处理）
  String? _lastSubtitlePath;

  // 轨道信息
  List<Map<String, dynamic>> _tracks = [];

  PlayerStateCallbacks? _callbacks;
  final List<StreamSubscription> _subscriptions = [];

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isPlaying => _isPlaying;

  @override
  bool get isBuffering => _isBuffering;

  @override
  bool get isCompleted => _isCompleted;

  @override
  Duration get position => _position;

  @override
  Duration get duration => _duration;

  @override
  double get speed => _speed;

  @override
  double get volume => _volume;

  @override
  double get progress {
    final dur = _duration.inMilliseconds;
    if (dur <= 0) return 0.0;
    return _position.inMilliseconds / dur;
  }

  @override
  bool get hasError => _errorMessage != null;

  @override
  String? get errorMessage => _errorMessage;

  @override
  bool get libassReady => true;

  @override
  int? get textureId => null;

  /// 当前可用的轨道列表
  List<Map<String, dynamic>> get tracks => _tracks;

  @override
  void setCallbacks(PlayerStateCallbacks callbacks) {
    _callbacks = callbacks;
  }

  @override
  Future<void> initialize({
    required String videoUrl,
    Duration? startPosition,
    bool dolbyVisionFix = false,
    bool useLibass = false,
  }) async {
    _logger.i('MpvAdapter', '开始初始化 media_kit 内核 (v2.1)');
    _logger.i('MpvAdapter', '视频URL: $videoUrl');
    _logger.i('MpvAdapter', '起始位置: ${startPosition?.inMilliseconds ?? 0}ms');
    _logger.i('MpvAdapter', 'DolbyVisionFix: $dolbyVisionFix');

    try {
      await dispose();

      _errorMessage = null;
      _isCompleted = false;
      _tracks = [];

      // 确保配置目录存在
      await _configManager.initialize();

      // 写入 mpv 配置文件（应用当前所有设置）
      await _configManager.writeConfig(
        subtitleFont: _subtitleFont,
        subtitleScale: _subtitleScale,
        subtitlePosition: _subtitlePosition,
        subtitleDelay: _subtitleDelay,
        audioDelay: _audioDelay,
        aspectRatio: _aspectRatio,
        glslShaders: _glslShaders,
      );

      // 创建 media_kit Player
      _logger.i('MpvAdapter', '创建 media_kit Player...');
      _player = Player();
      _logger.i('MpvAdapter', 'media_kit Player 创建成功');

      // 创建 VideoController
      _logger.i('MpvAdapter', '创建 VideoController...');
      _videoController = VideoController(_player!);
      _logger.i('MpvAdapter', 'VideoController 创建成功');

      // 监听状态变化
      _setupStreamListeners();

      // 加载视频
      _logger.i('MpvAdapter', '加载视频: $videoUrl');
      await _player!.open(Media(videoUrl));

      // 设置起始位置
      if (startPosition != null && startPosition > Duration.zero) {
        _logger.i('MpvAdapter', '设置起始位置: ${startPosition.inMilliseconds}ms');
        await _player!.seek(startPosition);
      }

      _isInitialized = true;
      _callbacks?.onDurationChanged?.call();
      _logger.i('MpvAdapter', 'media_kit 初始化完成');
    } catch (e, stackTrace) {
      _errorMessage = e.toString();
      _isInitialized = false;
      _logger.eWithStack('MpvAdapter', 'media_kit 初始化失败', e, stackTrace);
      _callbacks?.onError?.call();
    }
  }

  void _setupStreamListeners() {
    if (_player == null) return;

    _subscriptions.add(_player!.stream.playing.listen((playing) {
      _isPlaying = playing;
      _callbacks?.onPlayingStateChanged?.call();
    }));

    _subscriptions.add(_player!.stream.position.listen((position) {
      _position = position;
      _callbacks?.onPositionChanged?.call();
    }));

    _subscriptions.add(_player!.stream.duration.listen((duration) {
      _duration = duration;
      _callbacks?.onDurationChanged?.call();
    }));

    _subscriptions.add(_player!.stream.buffering.listen((buffering) {
      _isBuffering = buffering;
      _callbacks?.onBufferingStateChanged?.call();
    }));

    _subscriptions.add(_player!.stream.completed.listen((completed) {
      if (completed) {
        _isCompleted = true;
        _callbacks?.onCompleted?.call();
      }
    }));

    _subscriptions.add(_player!.stream.error.listen((error) {
      _errorMessage = error.toString();
      _logger.e('MpvAdapter', '播放器错误: $_errorMessage');
      _callbacks?.onError?.call();
    }));

    _subscriptions.add(_player!.stream.tracks.listen((tracks) {
      final trackList = <Map<String, dynamic>>[];

      for (final track in tracks.video) {
        trackList.add({
          'id': track.id,
          'type': 'video',
          'title': track.title ?? '',
          'language': track.language ?? '',
          'codec': track.codec ?? '',
        });
      }

      for (final track in tracks.audio) {
        trackList.add({
          'id': track.id,
          'type': 'audio',
          'title': track.title ?? '',
          'language': track.language ?? '',
          'codec': track.codec ?? '',
        });
      }

      for (final track in tracks.subtitle) {
        trackList.add({
          'id': track.id,
          'type': 'text',
          'title': track.title ?? '',
          'language': track.language ?? '',
          'codec': track.codec ?? '',
        });
      }

      _tracks = trackList;
      _logger.d('MpvAdapter', '轨道变更: ${_tracks.length} 条轨道');
    }));
  }

  // ========== 字幕处理 ==========

  @override
  Future<void> loadLibassSubtitle(String path) async {
    _logger.i('MpvAdapter', '加载字幕: $path');
    if (_player == null) return;

    try {
      _lastSubtitlePath = path;

      // 检测是否为图形字幕（PGS/SUP）
      if (SubtitleProcessor.isGraphicalSubtitle(path)) {
        _logger.i('MpvAdapter', '检测到图形字幕 (PGS/SUP)，直接加载');
        await _player!.setSubtitleTrack(SubtitleTrack.uri(path));
        return;
      }

      // 处理字幕：应用当前时间轴偏移和样式
      var processedPath = path;

      // 1. 调整时间轴（字幕延迟）
      if (_subtitleDelay != 0.0) {
        processedPath = await SubtitleProcessor.adjustTiming(
          processedPath,
          _subtitleDelay,
        );
      }

      // 2. 修改 ASS 样式（字体、大小、位置）
      if (SubtitleProcessor.detectFormat(path) == 'ass') {
        final marginV = _subtitlePosition != 100.0
            ? ((100.0 - _subtitlePosition) * 10).round()
            : null;
        final fontSize = _subtitleScale != 1.0
            ? (24 * _subtitleScale).round()
            : null;

        if (_subtitleFont != null || fontSize != null || marginV != null) {
          processedPath = await SubtitleProcessor.modifyAssStyle(
            processedPath,
            fontName: _subtitleFont,
            fontSize: fontSize,
            marginV: marginV,
          );
        }
      }

      await _player!.setSubtitleTrack(SubtitleTrack.uri(processedPath));
      _logger.i('MpvAdapter', '字幕加载成功: $processedPath');
    } catch (e, stackTrace) {
      _logger.eWithStack('MpvAdapter', '字幕加载失败', e, stackTrace);
    }
  }

  @override
  Future<void> loadLibassSubtitleMemory(Uint8List data, {String codec = 'ass'}) async {
    _logger.i('MpvAdapter', '加载内存字幕 - codec=$codec, size=${data.length} bytes');
    if (_player == null) return;
    try {
      final dataStr = String.fromCharCodes(data);
      await _player!.setSubtitleTrack(
        SubtitleTrack.data(dataStr, title: 'subtitle', language: 'und'),
      );
      _logger.i('MpvAdapter', '内存字幕加载成功');
    } catch (e, stackTrace) {
      _logger.eWithStack('MpvAdapter', '内存字幕加载失败', e, stackTrace);
    }
  }

  /// 加载外挂字幕（URL 或本地路径）
  Future<void> loadSubtitle(String url) async {
    await loadLibassSubtitle(url);
  }

  // ========== 高级功能实现 ==========

  @override
  Future<void> setSubtitleDelay(double seconds) async {
    _subtitleDelay = seconds;
    _logger.i('MpvAdapter', '设置字幕延迟: ${seconds}s');

    // 如果有已加载的字幕，重新处理并加载
    if (_lastSubtitlePath != null && _player != null) {
      await loadLibassSubtitle(_lastSubtitlePath!);
    }

    // 同时更新配置文件（下次播放生效）
    await _configManager.updateConfigValue('sub-delay', seconds.toStringAsFixed(3));
  }

  @override
  Future<void> setAudioDelay(double seconds) async {
    _audioDelay = seconds;
    _logger.i('MpvAdapter', '设置音频延迟: ${seconds}s');
    // 更新配置文件（下次播放生效）
    await _configManager.updateConfigValue('audio-delay', seconds.toStringAsFixed(3));
  }

  @override
  Future<void> setSubtitleFont(String fontName) async {
    _subtitleFont = fontName;
    _logger.i('MpvAdapter', '设置字幕字体: $fontName');

    // 如果有已加载的 ASS 字幕，重新处理并加载
    if (_lastSubtitlePath != null &&
        SubtitleProcessor.detectFormat(_lastSubtitlePath!) == 'ass') {
      await loadLibassSubtitle(_lastSubtitlePath!);
    }

    // 更新配置文件（下次播放生效）
    if (fontName.isNotEmpty) {
      await _configManager.updateConfigValue('sub-font', '"$fontName"');
    }
  }

  @override
  Future<void> setSubtitleSize(double size) async {
    // size 范围 0.0-1.0，映射到 0.5-1.5 的缩放比例
    _subtitleScale = 0.5 + size;
    _logger.i('MpvAdapter', '设置字幕大小: scale=$_subtitleScale');

    // 如果有已加载的 ASS 字幕，重新处理并加载
    if (_lastSubtitlePath != null &&
        SubtitleProcessor.detectFormat(_lastSubtitlePath!) == 'ass') {
      await loadLibassSubtitle(_lastSubtitlePath!);
    }

    // 更新配置文件（下次播放生效）
    await _configManager.updateConfigValue('sub-scale', _subtitleScale.toStringAsFixed(2));
  }

  @override
  Future<void> setSubtitlePosition(double position) async {
    // position 范围 0.0-1.0，映射到 100-0（mpv: 100=底部, 0=顶部）
    _subtitlePosition = 100 - position * 100;
    _logger.i('MpvAdapter', '设置字幕位置: pos=$_subtitlePosition');

    // 如果有已加载的 ASS 字幕，重新处理并加载
    if (_lastSubtitlePath != null &&
        SubtitleProcessor.detectFormat(_lastSubtitlePath!) == 'ass') {
      await loadLibassSubtitle(_lastSubtitlePath!);
    }

    // 更新配置文件（下次播放生效）
    await _configManager.updateConfigValue('sub-pos', _subtitlePosition.toStringAsFixed(1));
  }

  @override
  Future<void> setAspectRatio(String ratio) async {
    _aspectRatio = ratio;
    _logger.i('MpvAdapter', '设置画面比例: $ratio');
    // 更新配置文件（下次播放生效）
    String value;
    switch (ratio) {
      case '16:9':
        value = '16/9';
      case '4:3':
        value = '4/3';
      case '21:9':
        value = '21/9';
      case '全屏':
        value = '-1';
      case '原始':
        value = '0';
      default:
        value = '-1';
    }
    await _configManager.updateConfigValue('video-aspect-override', value);
  }

  @override
  Future<void> applySuperResolution(bool enable) async {
    _logger.i('MpvAdapter', '设置超分辨率: $enable');
    if (enable) {
      _glslShaders = [
        '~~/shaders/Anime4K_Clamp_Highlights.glsl',
        '~~/shaders/Anime4K_Restore_CNN_M.glsl',
        '~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl',
        '~~/shaders/Anime4K_AutoDownscalePre_x2.glsl',
        '~~/shaders/Anime4K_AutoDownscalePre_x4.glsl',
        '~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl',
      ];
    } else {
      _glslShaders = null;
    }
    // 更新配置文件（下次播放生效）
    if (_glslShaders != null) {
      final paths = _glslShaders!.join(':');
      await _configManager.updateConfigValue('glsl-shaders', '"$paths"');
    } else {
      await _configManager.updateConfigValue('glsl-shaders', '');
    }
  }

  // ========== 基础控制 ==========

  @override
  Widget buildVideo() {
    if (_videoController != null) {
      return Video(
        controller: _videoController!,
        fit: BoxFit.contain,
      );
    }
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  @override
  Future<void> play() async {
    if (_player == null) return;
    _logger.d('MpvAdapter', '播放');
    await _player!.play();
    _isCompleted = false;
  }

  @override
  Future<void> pause() async {
    if (_player == null) return;
    _logger.d('MpvAdapter', '暂停');
    await _player!.pause();
  }

  @override
  Future<void> seekTo(Duration position) async {
    if (_player == null || !_isInitialized) return;
    final clamped = Duration(
      milliseconds: max(0, min(position.inMilliseconds, _duration.inMilliseconds)),
    );
    _logger.d('MpvAdapter', '跳转: ${clamped.inMilliseconds}ms');
    await _player!.seek(clamped);
    _isCompleted = false;
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (_player == null || !_isInitialized) return;
    final clamped = speed.clamp(0.25, 4.0);
    _logger.d('MpvAdapter', '设置速度: ${clamped}x');
    await _player!.setRate(clamped);
    _speed = clamped;
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_player == null || !_isInitialized) return;
    final clamped = volume.clamp(0.0, 1.0);
    await _player!.setVolume(clamped * 100);
    _volume = clamped;
  }

  @override
  Future<Uint8List?> screenshot() async {
    if (_player == null) return null;
    try {
      final image = await _player!.screenshot();
      return image;
    } catch (e, stackTrace) {
      _logger.eWithStack('MpvAdapter', '截图失败', e, stackTrace);
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    _logger.i('MpvAdapter', '释放资源...');

    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    if (_player != null) {
      await _player!.dispose();
      _player = null;
    }
    _videoController = null;

    _isInitialized = false;
    _isPlaying = false;
    _isBuffering = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _tracks = [];
    _lastSubtitlePath = null;
    _logger.i('MpvAdapter', '资源已释放');
  }
}
