import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/api/api_interfaces.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/media_providers.dart';
import '../../../core/services/video_player_service.dart';

/// 播放页
class PlayerScreen extends ConsumerStatefulWidget {
  final String itemId;
  final String? mediaSourceId;

  const PlayerScreen({super.key, required this.itemId, this.mediaSourceId});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> with WidgetsBindingObserver {
  late VideoPlayerService _playerService;
  bool _showRemaining = false;
  bool _isLongPressing = false;
  Timer? _longPressTimer;
  Timer? _sleepTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playerService = VideoPlayerService();
    _playerService.addListener(_onPlayerUpdate);
    _initializePlayer();
    
    // 监听播放器设置变化并下发到播放器
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual(subtitleDelayProvider, (prev, next) {
        if (prev != next) _playerService.setSubtitleDelay(next);
      });
      ref.listenManual(audioDelayProvider, (prev, next) {
        if (prev != next) _playerService.setAudioDelay(next);
      });
      ref.listenManual(subtitleSizeProvider, (prev, next) {
        if (prev != next) _playerService.setSubtitleSize(next);
      });
      ref.listenManual(subtitlePositionProvider, (prev, next) {
        if (prev != next) _playerService.setSubtitlePosition(next);
      });
      ref.listenManual(subtitleFontProvider, (prev, next) {
        if (prev != next) _playerService.setSubtitleFont(next);
      });
    });
  }

  Future<void> _initializePlayer() async {
    final api = ref.read(apiClientProvider);
    final item = await api.media.getItemDetails(widget.itemId);

    final playbackInfo = await api.playback.getPlaybackInfo(widget.itemId);
    final mediaSource = playbackInfo.mediaSources.firstOrNull;

    final videoUrl = api.playback.getVideoStreamUrl(widget.itemId);

    Duration? startPosition;
    if (item.userData?.playbackPositionTicks != null) {
      startPosition = Duration(
        milliseconds: (item.userData!.playbackPositionTicks! / 10000).round(),
      );
    }

    ref.read(currentPlayingItemProvider.notifier).state = item;

    final coreString = ref.read(playerCoreProvider);
    final coreType = coreString == 'media_kit'
        ? PlayerCoreType.mediaKit
        : PlayerCoreType.videoPlayer;

    final dolbyVisionFix = coreType == PlayerCoreType.mediaKit
        ? ref.read(mpvDolbyVisionFixProvider)
        : false;
    final useLibass = coreType == PlayerCoreType.videoPlayer
        ? ref.read(exoLibassProvider)
        : false;

    await _playerService.initialize(
      videoUrl: videoUrl,
      itemId: widget.itemId,
      mediaSourceId: mediaSource?.id,
      startPosition: startPosition,
      coreType: coreType,
      dolbyVisionFix: dolbyVisionFix,
      useLibass: useLibass,
      onStart: (info) async {
        try {
          await api.playback.reportPlaybackStart(info);
        } catch (_) {}
      },
      onProgress: (info) async {
        try {
          await api.playback.reportPlaybackProgress(info);
        } catch (_) {}
      },
      onStop: (info) async {
        try {
          await api.playback.reportPlaybackStopped(info);
        } catch (_) {}
      },
    );

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    if (useLibass && _playerService.libassReady && mediaSource != null) {
      await _loadLibassSubtitles(item, mediaSource);
    }
  }

  Future<void> _loadLibassSubtitles(MediaItem item, MediaSource mediaSource) async {
    final api = ref.read(apiClientProvider);
    final subtitleStreams = mediaSource.mediaStreams
        .where((s) => s.isSubtitle)
        .toList();
    if (subtitleStreams.isEmpty) return;

    final preferredLang = ref.read(preferredSubtitleLanguageProvider);
    final target = subtitleStreams.firstWhere(
      (s) => s.language == preferredLang,
      orElse: () => subtitleStreams.first,
    );

    final codec = target.codec?.toLowerCase() ?? 'ass';
    final subUrl = api.playback.getSubtitleStreamUrl(
      widget.itemId,
      mediaSource.id,
      target.index,
      codec == 'ass' || codec == 'ssa' ? codec : 'ass',
    );

    await _playerService.loadLibassSubtitle(subUrl);
  }

  void _onPlayerUpdate() {
    setState(() {});
    _checkSkipOpening();
  }

  void _checkSkipOpening() {
    final openingStart = ref.read(skipOpeningStartProvider);
    final openingEnd = ref.read(skipOpeningEndProvider);
    final autoSkip = ref.read(skipAutoModeProvider);
    if (openingStart <= 0 || openingEnd <= 0 || openingEnd <= openingStart) return;

    final pos = _playerService.position.inSeconds;
    if (pos >= openingStart && pos < openingEnd) {
      if (autoSkip) {
        _playerService.seekTo(Duration(seconds: openingEnd));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已自动跳过片头')),
        );
      } else {
        // 显示跳过按钮 - 简化处理，直接在进度条上方显示 SnackBar
        // 这里用 ScaffoldMessenger 可能太频繁，暂不实现浮动按钮
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _playerService.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playerService.removeListener(_onPlayerUpdate);
    _playerService.dispose();
    _longPressTimer?.cancel();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(currentPlayingItemProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onTap: _playerService.toggleControls,
            onDoubleTapDown: _onDoubleTapDown,
            onLongPressStart: (_) => _onLongPressStart(),
            onLongPressEnd: (_) => _onLongPressEnd(),
            onHorizontalDragStart: (details) => _playerService.onDragStart(details, constraints),
            onHorizontalDragUpdate: (details) => _playerService.onDragUpdate(details, constraints),
            onHorizontalDragEnd: _playerService.onDragEnd,
            onVerticalDragStart: (details) => _playerService.onDragStart(details, constraints),
            onVerticalDragUpdate: (details) => _playerService.onDragUpdate(details, constraints),
            onVerticalDragEnd: _playerService.onDragEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildVideoArea(),

                if (_playerService.isBuffering)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),

                if (_playerService.hasError)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.white, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          '播放失败: ${_playerService.errorMessage}',
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _initializePlayer,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),

                // 亮度/音量手势指示器
                if (_playerService.isDragging)
                  _buildGestureIndicator(),

                // 长按快进指示器
                if (_isLongPressing)
                  _buildLongPressIndicator(),

                // 控制层
                if (_playerService.showControls && !_playerService.isLocked)
                  _buildControlsOverlay(item),

                // 锁定按钮（始终显示）
                if (_playerService.isLocked)
                  Positioned(
                    top: 40,
                    left: 16,
                    child: IconButton(
                      icon: const Icon(Icons.lock, color: Colors.white),
                      onPressed: _playerService.toggleLock,
                    ),
                  ),

                // 拖动进度提示
                if (_playerService.isDragging)
                  _buildDragIndicator(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildVideoArea() {
    return _playerService.buildVideoWidget();
  }

  void _onDoubleTapDown(TapDownDetails details) {
    if (_playerService.isLocked) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final tapX = details.globalPosition.dx;

    if (tapX < screenWidth / 3) {
      _playerService.seekBy(Duration(seconds: -ref.read(skipForwardStepProvider)));
    } else if (tapX > screenWidth * 2 / 3) {
      _playerService.seekBy(Duration(seconds: ref.read(skipForwardStepProvider)));
    } else {
      _playerService.togglePlay();
    }
  }

  void _onLongPressStart() {
    if (_playerService.isLocked) return;
    setState(() => _isLongPressing = true);
    _longPressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_isLongPressing) {
        _playerService.setSpeed(ref.read(longPressSpeedProvider));
      }
    });
  }

  void _onLongPressEnd() {
    setState(() => _isLongPressing = false);
    _longPressTimer?.cancel();
    _playerService.setSpeed(ref.read(defaultPlaybackSpeedProvider));
  }

  Widget _buildGestureIndicator() {
    final screenWidth = MediaQuery.of(context).size.width;
    final dragX = screenWidth / 2; // Simplified

    String label;
    IconData icon;
    double value;

    if (dragX < screenWidth / 2) {
      // 左侧：亮度
      label = '亮度';
      icon = Icons.brightness_high;
      value = _playerService.brightness;
    } else {
      // 右侧：音量
      label = '音量';
      icon = Icons.volume_up;
      value = _playerService.volume;
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 100,
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(value * 100).toInt()}%',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLongPressIndicator() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fast_forward, color: Colors.white, size: 32),
            const SizedBox(height: 8),
            Text(
              '${ref.read(longPressSpeedProvider)}x 快进中',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsOverlay(MediaItem? item) {
    return AnimatedOpacity(
      opacity: _playerService.showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        color: Colors.black.withValues(alpha: 0.4),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(item),
              Expanded(
                child: Row(
                  children: [
                    _buildLeftSideControls(),
                    const Spacer(),
                    _buildRightSideControls(),
                  ],
                ),
              ),
              _buildProgressBar(),
              _buildBottomBar(item),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(MediaItem? item) {
    final coreString = ref.read(playerCoreProvider);
    final isMpv = coreString == 'media_kit';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          Expanded(
            child: _MarqueeText(
              text: item?.name ?? widget.itemId,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          if (isMpv)
            IconButton(
              icon: const Icon(Icons.hd, color: Colors.white),
              tooltip: '超分 (Anime4K)',
              onPressed: () async {
                await _playerService.applySuperResolution(true);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已开启 Anime4K 超分辨率')),
                  );
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.skip_next, color: Colors.white),
            tooltip: '跳过片头/片尾',
            onPressed: _showSkipDialog,
          ),
          IconButton(
            icon: Icon(
              ref.read(hardwareDecodingProvider) ? Icons.memory : Icons.slow_motion_video,
              color: Colors.white,
            ),
            tooltip: '硬解/软解',
            onPressed: () {
              final current = ref.read(hardwareDecodingProvider);
              ref.read(hardwareDecodingProvider.notifier).state = !current;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(!current ? '已切换硬件解码' : '已切换软件解码')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: _showMoreMenu,
          ),
        ],
      ),
    );
  }

  Widget _buildLeftSideControls() {
    return SizedBox(
      width: 60,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.camera_alt, color: Colors.white),
            tooltip: '截图',
            onPressed: _takeScreenshot,
          ),
          IconButton(
            icon: Icon(
              _playerService.isLocked ? Icons.lock : Icons.lock_open,
              color: Colors.white,
            ),
            tooltip: '锁定',
            onPressed: _playerService.toggleLock,
          ),
        ],
      ),
    );
  }

  Widget _buildRightSideControls() {
    return SizedBox(
      width: 60,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () {
              final newSpeed = (_playerService.speed + 0.25).clamp(0.25, 4.0);
              _playerService.setSpeed(newSpeed);
            },
          ),
          Text(
            '${_playerService.speed}x',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove, color: Colors.white),
            onPressed: () {
              final newSpeed = (_playerService.speed - 0.25).clamp(0.25, 4.0);
              _playerService.setSpeed(newSpeed);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final currentTime = _formatDuration(_playerService.position);
    final remainingTime = _formatDuration(_playerService.duration - _playerService.position);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _showRemaining = !_showRemaining),
                child: Text(
                  _showRemaining ? '-$remainingTime' : currentTime,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF5B8DEF),
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                    thumbColor: const Color(0xFF5B8DEF),
                    overlayColor: const Color(0xFF5B8DEF).withValues(alpha: 0.2),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: _playerService.progress.clamp(0.0, 1.0),
                    onChanged: (value) {
                      final position = Duration(
                        milliseconds: (value * _playerService.duration.inMilliseconds).round(),
                      );
                      _playerService.seekTo(position);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatDuration(_playerService.duration),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(MediaItem? item) {
    final isPlaying = _playerService.isPlaying;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.skip_previous, color: Colors.white),
            tooltip: '上一集',
            onPressed: _playPrevious,
          ),
          IconButton(
            icon: const Icon(Icons.replay_10, color: Colors.white),
            tooltip: '快退 10s',
            onPressed: () => _playerService.seekBy(const Duration(seconds: -10)),
          ),
          IconButton(
            icon: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 40,
            ),
            tooltip: '播放/暂停',
            onPressed: _playerService.togglePlay,
          ),
          IconButton(
            icon: const Icon(Icons.forward_10, color: Colors.white),
            tooltip: '快进 10s',
            onPressed: () => _playerService.seekBy(const Duration(seconds: 10)),
          ),
          IconButton(
            icon: const Icon(Icons.skip_next, color: Colors.white),
            tooltip: '下一集',
            onPressed: _playNext,
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
            tooltip: '弹幕设置',
            onPressed: _showDanmakuSettings,
          ),
          IconButton(
            icon: const Icon(Icons.subtitles, color: Colors.white),
            tooltip: '字幕设置',
            onPressed: _showSubtitleSettings,
          ),
          IconButton(
            icon: const Icon(Icons.audiotrack, color: Colors.white),
            tooltip: '音频设置',
            onPressed: _showAudioSettings,
          ),
          IconButton(
            icon: const Icon(Icons.playlist_play, color: Colors.white),
            tooltip: '选集',
            onPressed: () => _showEpisodeSelector(item),
          ),
        ],
      ),
    );
  }

  Widget _buildDragIndicator() {
    final isForward = _playerService.position > _playerService.duration ~/ 2;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isForward ? Icons.forward_10 : Icons.replay_10,
              color: Colors.white,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              _formatDuration(_playerService.position),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _playPrevious() async {
    final currentItem = ref.read(currentPlayingItemProvider);
    if (currentItem?.seriesId != null) {
      try {
        final episodes = await ref.read(apiClientProvider).media.getEpisodes(
          currentItem!.seriesId!,
          seasonId: currentItem.seasonId,
        );
        final currentIndex = episodes.indexWhere((e) => e.id == currentItem.id);
        if (currentIndex > 0) {
          final prevEpisode = episodes[currentIndex - 1];
          if (mounted) {
            context.replace('/player/${prevEpisode.id}');
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已经是第一集了')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('加载失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _playNext() async {
    final currentItem = ref.read(currentPlayingItemProvider);
    if (currentItem?.seriesId != null) {
      try {
        final episodes = await ref.read(apiClientProvider).media.getEpisodes(
          currentItem!.seriesId!,
          seasonId: currentItem.seasonId,
        );
        final currentIndex = episodes.indexWhere((e) => e.id == currentItem.id);
        if (currentIndex >= 0 && currentIndex < episodes.length - 1) {
          final nextEpisode = episodes[currentIndex + 1];
          if (mounted) {
            context.replace('/player/${nextEpisode.id}');
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已经是最后一集了')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('加载失败: $e')),
          );
        }
      }
    }
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.route, color: Colors.white),
              title: const Text('线路切换', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showLineSelector();
              },
            ),
            ListTile(
              leading: const Icon(Icons.screen_rotation, color: Colors.white),
              title: const Text('旋转屏幕', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _toggleOrientation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.white),
              title: const Text('定时关闭', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showTimerDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.memory, color: Colors.white),
              title: const Text('内核切换', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showCoreSwitchDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.analytics, color: Colors.white),
              title: const Text('统计信息', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showStats();
              },
            ),
            ListTile(
              leading: const Icon(Icons.aspect_ratio, color: Colors.white),
              title: const Text('画面比例', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showAspectRatioDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSkipDialog() {
    showDialog(
      context: context,
      builder: (context) => _SkipDialog(currentPosition: _playerService.position),
    );
  }

  void _toggleOrientation() {
    final orientation = MediaQuery.of(context).orientation;
    if (orientation == Orientation.portrait) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  Future<void> _takeScreenshot() async {
    try {
      final data = await _playerService.screenshot();
      if (data != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('截图已保存')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('截图功能暂不支持当前播放器内核')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('截图失败: $e')),
      );
    }
  }

  void _showStats() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('播放统计'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('播放速度: ${_playerService.speed}x'),
            Text('音量: ${(_playerService.volume * 100).toInt()}%'),
            Text('亮度: ${(_playerService.brightness * 100).toInt()}%'),
            Text('播放状态: ${_playerService.isPlaying ? "播放中" : "已暂停"}'),
            Text('当前位置: ${_formatDuration(_playerService.position)} / ${_formatDuration(_playerService.duration)}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  void _showDanmakuSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => const _DanmakuSettingsSheet(),
    );
  }

  void _showSubtitleSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _SubtitleSettingsSheet(
          scrollController: scrollController,
        ),
      ),
    );
  }

  void _showAudioSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => _AudioSettingsSheet(
          scrollController: scrollController,
        ),
      ),
    );
  }

  void _showEpisodeSelector(MediaItem? item) {
    if (item?.seriesId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return _EpisodeSelectorSheet(
            scrollController: scrollController,
            seriesId: item!.seriesId!,
            currentEpisodeId: item.id,
          );
        },
      ),
    );
  }

  void _showTimerDialog() {
    final options = [15, 30, 45, 60, 90, 120];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('定时关闭'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((minutes) => ListTile(
            title: Text('$minutes 分钟后关闭'),
            onTap: () {
              Navigator.pop(context);
              _startSleepTimer(Duration(minutes: minutes));
            },
          )).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ],
      ),
    );
  }

  void _startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepTimer = Timer(duration, () {
      if (mounted) {
        _playerService.pause();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已定时关闭播放')),
        );
      }
      _sleepTimer = null;
    });
    ref.read(sleepTimerRemainingProvider.notifier).state = duration;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已设置 ${duration.inMinutes} 分钟后关闭')),
    );
  }

  void _showCoreSwitchDialog() {
    final currentCore = ref.read(playerCoreProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换播放器内核'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('ExoPlayer/AVPlayer'),
              subtitle: const Text('轻量稳定', style: TextStyle(fontSize: 12)),
              leading: currentCore == 'video_player'
                  ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                Navigator.pop(context);
                if (currentCore != 'video_player') {
                  _switchCore('video_player');
                }
              },
            ),
            ListTile(
              title: const Text('MPV (media_kit)'),
              subtitle: const Text('支持PGS/SUP字幕、HDR', style: TextStyle(fontSize: 12)),
              leading: currentCore == 'media_kit'
                  ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                Navigator.pop(context);
                if (currentCore != 'media_kit') {
                  _switchCore('media_kit');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchCore(String core) async {
    final savedPosition = _playerService.position;
    ref.read(playerCoreProvider.notifier).state = core;
    await _playerService.dispose();
    _playerService = VideoPlayerService();
    _playerService.addListener(_onPlayerUpdate);
    await _initializePlayer();
    if (savedPosition > Duration.zero) {
      await _playerService.seekTo(savedPosition);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到 ${core == 'media_kit' ? 'MPV' : 'ExoPlayer/AVPlayer'}')),
      );
    }
  }

  void _showLineSelector() {
    final server = ref.read(currentServerProvider);
    if (server == null || server.lines.length <= 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前只有一个可用线路')),
        );
      }
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择线路', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            const Divider(color: Colors.white24),
            ...server.lines.asMap().entries.map((entry) {
              final idx = entry.key;
              final line = entry.value;
              return ListTile(
                leading: const Icon(Icons.route, color: Colors.white70),
                title: Text(line.name, style: const TextStyle(color: Colors.white)),
                trailing: idx == server.activeLineIndex
                    ? const Icon(Icons.check, color: Color(0xFF5B8DEF))
                    : null,
                onTap: () {
                  ref.read(serverListProvider.notifier).setActiveLine(server.id, idx);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已切换到线路: ${line.name}')),
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showAspectRatioDialog() {
    final ratios = ['自动', '16:9', '4:3', '21:9', '全屏', '原始'];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('画面比例'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ratios.map((ratio) => ListTile(
            title: Text(ratio),
            trailing: ref.read(aspectRatioProvider) == ratio
                ? const Icon(Icons.check, color: Color(0xFF5B8DEF))
                : null,
            onTap: () {
              ref.read(aspectRatioProvider.notifier).state = ratio;
              _playerService.setAspectRatio(ratio);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('画面比例: $ratio')),
              );
            },
          )).toList(),
        ),
      ),
    );
  }
}

/// 滚动文字组件
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _MarqueeText({required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    );
    _animation = Tween<double>(begin: 1.0, end: -1.0).animate(_controller);
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return FractionalTranslation(
            translation: Offset(_animation.value, 0),
            child: Text(
              widget.text,
              maxLines: 1,
              overflow: TextOverflow.visible,
              style: widget.style,
            ),
          );
        },
      ),
    );
  }
}

/// 跳过片头/片尾弹窗
class _SkipDialog extends ConsumerStatefulWidget {
  final Duration currentPosition;

  const _SkipDialog({required this.currentPosition});

  @override
  ConsumerState<_SkipDialog> createState() => _SkipDialogState();
}

class _SkipDialogState extends ConsumerState<_SkipDialog> {
  late Duration _openingStart;
  late Duration _openingEnd;
  late bool _autoSkip;

  @override
  void initState() {
    super.initState();
    final openingStartSec = ref.read(skipOpeningStartProvider);
    final openingEndSec = ref.read(skipOpeningEndProvider);
    _openingStart = Duration(seconds: openingStartSec);
    _openingEnd = Duration(seconds: openingEndSec);
    _autoSkip = ref.read(skipAutoModeProvider);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('跳过片头'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('开始时间'),
              const Spacer(),
              Text(_formatTime(_openingStart)),
              IconButton(
                icon: const Icon(Icons.location_on),
                tooltip: '取当前时间',
                onPressed: () {
                  setState(() => _openingStart = widget.currentPosition);
                },
              ),
            ],
          ),
          Row(
            children: [
              const Text('结束时间'),
              const Spacer(),
              Text(_formatTime(_openingEnd)),
              IconButton(
                icon: const Icon(Icons.location_on),
                tooltip: '取当前时间',
                onPressed: () {
                  setState(() => _openingEnd = widget.currentPosition);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('跳过模式'),
              const Spacer(),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('显示按钮')),
                  ButtonSegment(value: true, label: Text('自动跳过')),
                ],
                selected: {_autoSkip},
                onSelectionChanged: (value) {
                  setState(() => _autoSkip = value.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '当前: ${_autoSkip ? "自动跳过" : "显示跳过按钮"}',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            ref.read(skipOpeningStartProvider.notifier).state = _openingStart.inSeconds;
            ref.read(skipOpeningEndProvider.notifier).state = _openingEnd.inSeconds;
            ref.read(skipAutoModeProvider.notifier).state = _autoSkip;
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('跳过设置已保存')),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }

  String _formatTime(Duration duration) {
    final m = duration.inMinutes.toString().padLeft(2, '0');
    final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 弹幕设置弹窗
class _DanmakuSettingsSheet extends StatelessWidget {
  const _DanmakuSettingsSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('弹幕设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          const Text('弹幕轨道'),
          ListTile(
            leading: const Icon(Icons.radio_button_checked),
            title: const Text('中文简体（默认）'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.radio_button_unchecked),
            title: const Text('中文繁体'),
            onTap: () {},
          ),
          const Divider(),
          const Text('字幕大小'),
          Slider(value: 0.5, onChanged: (_) {}),
          const Text('字幕位置'),
          Slider(value: 0.5, onChanged: (_) {}),
        ],
      ),
    );
  }
}

/// 字幕设置弹窗
class _SubtitleSettingsSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;

  const _SubtitleSettingsSheet({required this.scrollController});

  @override
  ConsumerState<_SubtitleSettingsSheet> createState() => _SubtitleSettingsSheetState();
}

class _SubtitleSettingsSheetState extends ConsumerState<_SubtitleSettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final item = ref.watch(currentPlayingItemProvider);
    final subtitleAsync = item != null ? ref.watch(playbackInfoProvider(item.id)) : null;
    final subtitleOffset = ref.watch(subtitleDelayProvider);
    final subtitleSize = ref.watch(subtitleSizeProvider);
    final subtitlePosition = ref.watch(subtitlePositionProvider);
    final subtitleFont = ref.watch(subtitleFontProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      child: subtitleAsync?.when(
            data: (info) {
              final subtitles = info.mediaSources.firstOrNull?.mediaStreams.where((s) => s.isSubtitle).toList() ?? [];
              final selectedIndex = ref.watch(subtitleTrackProvider);

              return ListView(
                controller: widget.scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text('字幕设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),

                  const Text('字幕轨道', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (subtitles.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.subtitles_off),
                      title: Text('无可用字幕'),
                    )
                  else
                    ...subtitles.map((stream) => RadioListTile<int>(
                      title: Text(stream.displayTitle ?? stream.language ?? '轨道 ${stream.index}'),
                      subtitle: stream.codec != null ? Text('编码: ${stream.codec}') : null,
                      value: stream.index,
                      groupValue: selectedIndex ?? subtitles.firstOrNull?.index,
                      onChanged: (value) {
                        ref.read(subtitleTrackProvider.notifier).state = value;
                      },
                    )),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickExternalSubtitle(),
                          icon: const Icon(Icons.upload_file),
                          label: const Text('导入字幕'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _searchOnlineSubtitle(item?.name ?? ''),
                          icon: const Icon(Icons.search),
                          label: const Text('在线搜索'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),

                  const Text('字体', style: TextStyle(fontWeight: FontWeight.w600)),
                  ListTile(
                    title: Text(subtitleFont),
                    trailing: const Icon(Icons.arrow_drop_down),
                    onTap: () => _showFontSelector(context),
                  ),
                  const Divider(),

                  const Text('字幕同步', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: () {
                          ref.read(subtitleDelayProvider.notifier).state = subtitleOffset - 0.5;
                        },
                      ),
                      Text(
                        '${subtitleOffset >= 0 ? "+" : ""}${subtitleOffset.toStringAsFixed(1)}s',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          ref.read(subtitleDelayProvider.notifier).state = subtitleOffset + 0.5;
                        },
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => _showCustomOffsetDialog(context),
                        child: const Text('自定义输入'),
                      ),
                      TextButton(
                        onPressed: () {
                          ref.read(subtitleDelayProvider.notifier).state = 0.0;
                        },
                        child: const Text('重置'),
                      ),
                    ],
                  ),
                  const Divider(),

                  const Text('字幕大小', style: TextStyle(fontWeight: FontWeight.w600)),
                  Slider(
                    value: subtitleSize,
                    onChanged: (value) {
                      ref.read(subtitleSizeProvider.notifier).state = value;
                    },
                  ),

                  const Text('字幕位置', style: TextStyle(fontWeight: FontWeight.w600)),
                  Slider(
                    value: subtitlePosition,
                    onChanged: (value) {
                      ref.read(subtitlePositionProvider.notifier).state = value;
                    },
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('加载字幕信息失败')),
          ) ??
          const Center(child: Text('无播放信息')),
    );
  }

  Future<void> _pickExternalSubtitle() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'ass', 'ssa', 'vtt'],
      );
      if (result != null && result.files.single.path != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已导入字幕: ${result.files.single.name}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    }
  }

  void _searchOnlineSubtitle(String title) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('在线搜索字幕功能开发中')),
      );
    }
  }

  void _showFontSelector(BuildContext context) {
    final fonts = ['默认', 'Arial', 'Helvetica', 'Times New Roman', 'Courier New'];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: fonts.map((font) => ListTile(
            title: Text(font),
            trailing: ref.read(subtitleFontProvider) == font
                ? const Icon(Icons.check, color: Color(0xFF5B8DEF))
                : null,
            onTap: () {
              ref.read(subtitleFontProvider.notifier).state = font;
              Navigator.pop(ctx);
            },
          )).toList(),
        ),
      ),
    );
  }

  void _showCustomOffsetDialog(BuildContext context) {
    final controller = TextEditingController(text: ref.read(subtitleDelayProvider).toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义字幕同步'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: const InputDecoration(
            labelText: '偏移量（秒）',
            hintText: '正数 = 延后，负数 = 提前',
            suffixText: 's',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              if (value != null) {
                ref.read(subtitleDelayProvider.notifier).state = value;
              }
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

/// 音频设置弹窗
class _AudioSettingsSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;

  const _AudioSettingsSheet({required this.scrollController});

  @override
  ConsumerState<_AudioSettingsSheet> createState() => _AudioSettingsSheetState();
}

class _AudioSettingsSheetState extends ConsumerState<_AudioSettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final item = ref.watch(currentPlayingItemProvider);
    final audioAsync = item != null ? ref.watch(playbackInfoProvider(item.id)) : null;
    final audioOffset = ref.watch(audioDelayProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      child: audioAsync?.when(
            data: (info) {
              final audios = info.mediaSources.firstOrNull?.mediaStreams.where((s) => s.isAudio).toList() ?? [];
              final selectedIndex = ref.watch(audioTrackProvider);

              return ListView(
                controller: widget.scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text('音频设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),

                  const Text('音频轨道', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (audios.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.audiotrack, color: Colors.grey),
                      title: Text('无可用音轨'),
                    )
                  else
                    ...audios.map((stream) => RadioListTile<int>(
                      title: Text(stream.displayTitle ?? stream.language ?? '轨道 ${stream.index}'),
                      subtitle: stream.codec != null ? Text('编码: ${stream.codec}') : null,
                      value: stream.index,
                      groupValue: selectedIndex ?? audios.firstOrNull?.index,
                      onChanged: (value) {
                        ref.read(audioTrackProvider.notifier).state = value;
                      },
                    )),
                  const Divider(),

                  const Text('音频同步', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: () {
                          ref.read(audioDelayProvider.notifier).state = audioOffset - 0.5;
                        },
                      ),
                      Text(
                        '${audioOffset >= 0 ? "+" : ""}${audioOffset.toStringAsFixed(1)}s',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          ref.read(audioDelayProvider.notifier).state = audioOffset + 0.5;
                        },
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => _showCustomOffsetDialog(context),
                        child: const Text('自定义输入'),
                      ),
                      TextButton(
                        onPressed: () {
                          ref.read(audioDelayProvider.notifier).state = 0.0;
                        },
                        child: const Text('重置'),
                      ),
                    ],
                  ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('加载音频信息失败')),
          ) ??
          const Center(child: Text('无播放信息')),
    );
  }

  void _showCustomOffsetDialog(BuildContext context) {
    final controller = TextEditingController(text: ref.read(audioDelayProvider).toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自定义音频同步'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: const InputDecoration(
            labelText: '偏移量（秒）',
            hintText: '正数 = 延后，负数 = 提前',
            suffixText: 's',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              if (value != null) {
                ref.read(audioDelayProvider.notifier).state = value;
              }
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

/// 选集弹窗
class _EpisodeSelectorSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final String seriesId;
  final String currentEpisodeId;

  const _EpisodeSelectorSheet({
    required this.scrollController,
    required this.seriesId,
    required this.currentEpisodeId,
  });

  @override
  ConsumerState<_EpisodeSelectorSheet> createState() => _EpisodeSelectorSheetState();
}

class _EpisodeSelectorSheetState extends ConsumerState<_EpisodeSelectorSheet> {
  String? _selectedSeasonId;
  bool _isGridView = false;

  @override
  Widget build(BuildContext context) {
    final seasonsAsync = ref.watch(seasonsProvider(widget.seriesId));
    final api = ref.read(apiClientProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 拖拽指示条
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 头部控制栏
          Row(
            children: [
              // 季选择
              seasonsAsync.when(
                data: (seasons) {
                  if (seasons.isEmpty) return const SizedBox.shrink();
                  return DropdownButton<String>(
                    value: _selectedSeasonId ?? seasons.first.id,
                    items: seasons.map((season) => DropdownMenuItem(
                      value: season.id,
                      child: Text(season.name),
                    )).toList(),
                    onChanged: (value) {
                      setState(() => _selectedSeasonId = value);
                    },
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const Spacer(),
              // 视图切换
              IconButton(
                icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                onPressed: () => setState(() => _isGridView = !_isGridView),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 集列表
          Expanded(
            child: _buildEpisodesList(api),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodesList(ApiClientFactory api) {
    final episodesAsync = ref.watch(episodesProvider((
      seriesId: widget.seriesId,
      seasonId: _selectedSeasonId,
    )));

    return episodesAsync.when(
      data: (episodes) {
        if (_isGridView) {
          return GridView.builder(
            controller: widget.scrollController,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              childAspectRatio: 1,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              final episode = episodes[index];
              final isCurrent = episode.id == widget.currentEpisodeId;
              final isWatched = episode.userData?.played ?? false;

              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  context.push('/player/${episode.id}');
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? const Color(0xFF5B8DEF).withValues(alpha: 0.2)
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: isCurrent
                        ? Border.all(color: const Color(0xFF5B8DEF), width: 2)
                        : null,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${episode.indexNumber}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: isCurrent ? const Color(0xFF5B8DEF) : null,
                          ),
                        ),
                        if (isWatched)
                          const Icon(Icons.check, color: Color(0xFF5B8DEF), size: 16),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }

        return ListView.builder(
          controller: widget.scrollController,
          itemCount: episodes.length,
          itemBuilder: (context, index) {
            final episode = episodes[index];
            final isCurrent = episode.id == widget.currentEpisodeId;
            final isWatched = episode.userData?.played ?? false;
            final imageUrl = episode.primaryImageTag != null
                ? api.image.getPrimaryImageUrl(episode.id, tag: episode.primaryImageTag, maxWidth: 200)
                : null;

            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 80,
                  height: 48,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: imageUrl != null
                      ? Image.network(imageUrl, fit: BoxFit.cover)
                      : const Center(child: Icon(Icons.play_arrow, size: 20)),
                ),
              ),
              title: Row(
                children: [
                  if (isWatched)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Icon(Icons.check_circle, size: 16, color: Color(0xFF5B8DEF)),
                    ),
                  Expanded(
                    child: Text(
                      'E${episode.indexNumber} ${episode.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                episode.formattedRuntime ?? '',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: isCurrent
                  ? const Icon(Icons.play_circle, color: Color(0xFF5B8DEF))
                  : null,
              selected: isCurrent,
              onTap: () {
                Navigator.pop(context);
                context.push('/player/${episode.id}');
              },
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('加载失败')),
    );
  }
}
