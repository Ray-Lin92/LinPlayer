import 'dart:async';
import 'dart:math' show max, min;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'player_adapter.dart';
import 'libass_bridge.dart';

/// video_player 适配器
/// 
/// 基于 ExoPlayer(Android) / AVPlayer(iOS) 实现
/// 支持通过 libass 渲染 ASS/SSA 特效字幕
class VideoPlayerAdapter implements PlayerAdapter {
  VideoPlayerController? _controller;
  Timer? _positionTimer;
  
  bool _isCompleted = false;
  String? _errorMessage;
  bool _useLibass = false;
  bool _libassReady = false;
  
  PlayerStateCallbacks? _callbacks;
  
  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  
  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;
  
  @override
  bool get isBuffering => _controller?.value.isBuffering ?? false;
  
  @override
  bool get isCompleted => _isCompleted;
  
  @override
  Duration get position => _controller?.value.position ?? Duration.zero;
  
  @override
  Duration get duration => _controller?.value.duration ?? Duration.zero;
  
  @override
  double get speed => _controller?.value.playbackSpeed ?? 1.0;
  
  @override
  double get volume => _controller?.value.volume ?? 1.0;
  
  @override
  double get progress {
    final dur = duration.inMilliseconds;
    if (dur <= 0) return 0.0;
    return position.inMilliseconds / dur;
  }
  
  @override
  bool get hasError => _errorMessage != null;
  
  @override
  String? get errorMessage => _errorMessage;
  
  @override
  bool get libassReady => _libassReady;
  
  @override
  void setCallbacks(PlayerStateCallbacks callbacks) {
    _callbacks = callbacks;
  }
  
  @override
  Widget buildVideoWidget() {
    if (!isInitialized || _controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final video = AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: VideoPlayer(_controller!),
    );
    if (_useLibass && _libassReady) {
      return Stack(
        children: [
          video,
          Positioned.fill(
            child: _LibassOverlay(adapter: this),
          ),
        ],
      );
    }
    return video;
  }
  
  @override
  Future<void> initialize({
    required String videoUrl,
    Duration? startPosition,
    bool dolbyVisionFix = false,
    bool useLibass = false,
  }) async {
    try {
      await dispose();
      
      _errorMessage = null;
      _isCompleted = false;
      _useLibass = useLibass;
      _libassReady = false;
      
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: true,
        ),
      );
      
      await _controller!.initialize();
      
      if (startPosition != null && startPosition > Duration.zero) {
        await _controller!.seekTo(startPosition);
      }
      
      _controller!.addListener(_onControllerUpdate);
      
      _positionTimer = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _callbacks?.onPositionChanged?.call(),
      );
      
      if (_useLibass) {
        await _initLibass();
      }
      
      _callbacks?.onDurationChanged?.call();
    } catch (e) {
      _errorMessage = e.toString();
      _callbacks?.onError?.call();
    }
  }
  
  Future<void> _initLibass() async {
    final available = await LibassBridge.isAvailable();
    if (!available) {
      _useLibass = false;
      return;
    }
    
    final size = _controller?.value.size ?? const Size(1920, 1080);
    final width = size.width.toInt();
    final height = size.height.toInt();
    if (width <= 0 || height <= 0) return;
    
    final ok = await LibassBridge.init(width: width, height: height);
    if (!ok) {
      _useLibass = false;
      return;
    }
    
    _libassReady = true;
  }
  
  @override
  Future<void> loadLibassSubtitle(String path) async {
    if (!_libassReady) return;
    await LibassBridge.loadSubFile(path);
  }
  
  @override
  Future<void> loadLibassSubtitleMemory(Uint8List data, {String codec = 'ass'}) async {
    if (!_libassReady) return;
    await LibassBridge.loadSubMemory(data, codec: codec);
  }
  
  @override
  Future<void> play() async {
    if (_controller == null) return;
    await _controller!.play();
    _isCompleted = false;
    _callbacks?.onPlayingStateChanged?.call();
  }
  
  @override
  Future<void> pause() async {
    if (_controller == null) return;
    await _controller!.pause();
    _callbacks?.onPlayingStateChanged?.call();
  }
  
  @override
  Future<void> seekTo(Duration position) async {
    if (_controller == null || !isInitialized) return;
    final clamped = Duration(
      milliseconds: max(0, min(position.inMilliseconds, duration.inMilliseconds)),
    );
    await _controller!.seekTo(clamped);
    _isCompleted = false;
    _callbacks?.onPositionChanged?.call();
  }
  
  @override
  Future<void> setSpeed(double speed) async {
    if (_controller == null || !isInitialized) return;
    final clamped = speed.clamp(0.25, 4.0);
    await _controller!.setPlaybackSpeed(clamped);
    _callbacks?.onPlayingStateChanged?.call();
  }
  
  @override
  Future<void> setVolume(double volume) async {
    if (_controller == null || !isInitialized) return;
    final clamped = volume.clamp(0.0, 1.0);
    await _controller!.setVolume(clamped);
  }
  
  void _onControllerUpdate() {
    if (_controller == null) return;
    
    final value = _controller!.value;
    
    if (value.isPlaying != isPlaying) {
      _callbacks?.onPlayingStateChanged?.call();
    }
    
    if (value.isBuffering != isBuffering) {
      _callbacks?.onBufferingStateChanged?.call();
    }
    
    // 检测播放完成
    if (value.position >= value.duration && value.duration > Duration.zero && !isCompleted) {
      _isCompleted = true;
      _callbacks?.onCompleted?.call();
    }
  }
  
  @override
  Future<void> dispose() async {
    if (_libassReady) {
      await LibassBridge.dispose();
      _libassReady = false;
    }
    
    _positionTimer?.cancel();
    _positionTimer = null;
    
    _controller?.removeListener(_onControllerUpdate);
    await _controller?.dispose();
    _controller = null;
  }
}

class _LibassOverlay extends StatefulWidget {
  final VideoPlayerAdapter adapter;
  const _LibassOverlay({required this.adapter});

  @override
  State<_LibassOverlay> createState() => _LibassOverlayState();
}

class _LibassOverlayState extends State<_LibassOverlay> {
  List<LibassBlendRect>? _rects;
  List<ui.Image>? _images;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 41), (_) => _render());
  }

  Future<void> _render() async {
    if (!mounted || !widget.adapter._libassReady) return;
    final ptsMs = widget.adapter.position.inMilliseconds;
    final rects = await LibassBridge.renderFrame(ptsMs);
    if (rects == null || rects.isEmpty || !mounted) {
      if (_images != null && _images!.isNotEmpty && mounted) {
        for (final img in _images!) {
          img.dispose();
        }
        setState(() {
          _rects = null;
          _images = null;
        });
      }
      return;
    }

    final images = <ui.Image>[];
    for (final rect in rects) {
      final image = await rect.toImage();
      images.add(image);
    }

    if (!mounted) {
      for (final img in images) {
        img.dispose();
      }
      return;
    }

    final oldImages = _images;
    setState(() {
      _rects = rects;
      _images = images;
    });

    for (final img in oldImages ?? <ui.Image>[]) {
      img.dispose();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final img in _images ?? <ui.Image>[]) {
      img.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_images == null || _images!.isEmpty) return const SizedBox.shrink();
    return CustomPaint(
      painter: _DecodedLibassPainter(_images!, _rects!),
      size: Size.infinite,
    );
  }
}

class _DecodedLibassPainter extends CustomPainter {
  final List<ui.Image> images;
  final List<LibassBlendRect> rects;

  _DecodedLibassPainter(this.images, this.rects);

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < images.length && i < rects.length; i++) {
      final paint = Paint()..filterQuality = FilterQuality.medium;
      canvas.drawImage(images[i], Offset.zero, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DecodedLibassPainter oldDelegate) => true;
}
