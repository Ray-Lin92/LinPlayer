import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_interfaces.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/media_providers.dart';

/// 播放页
class PlayerScreen extends ConsumerStatefulWidget {
  final String itemId;
  
  const PlayerScreen({super.key, required this.itemId});
  
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _showControls = true;
  bool _isLocked = false;
  double _currentPosition = 0.0;
  double _duration = 3600.0;
  bool _showRemaining = false;
  PlaybackInfo? _playbackInfo;
  MediaItem? _itemInfo;
  bool _hasReportedStart = false;
  
  @override
  void initState() {
    super.initState();
    _initPlayback();
  }
  
  Future<void> _initPlayback() async {
    try {
      final api = ref.read(apiClientProvider);
      final info = await api.playback.getPlaybackInfo(widget.itemId);
      final item = await api.media.getItemDetails(widget.itemId);
      if (mounted) {
        setState(() {
          _playbackInfo = info;
          _itemInfo = item;
          _duration = (item.runTimeTicks ?? 54000000000) / 10000000.0;
          if (item.userData?.playbackPositionTicks != null) {
            _currentPosition = item.userData!.playbackPositionTicks! / 10000000.0;
          }
        });
        await _reportStart();
        ref.read(isPlayingProvider.notifier).state = true;
        ref.read(currentPlayingItemProvider.notifier).state = item;
      }
    } catch (_) {}
  }
  
  Future<void> _reportStart() async {
    if (_hasReportedStart || _playbackInfo == null) return;
    _hasReportedStart = true;
    try {
      final api = ref.read(apiClientProvider);
      await api.playback.reportPlaybackStart(PlaybackStartInfo(
        itemId: widget.itemId,
        mediaSourceId: _playbackInfo!.mediaSources.firstOrNull?.id ?? '',
      ));
    } catch (_) {}
  }
  
  Future<void> _reportProgress() async {
    if (_playbackInfo == null) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.playback.reportPlaybackProgress(PlaybackProgressInfo(
        itemId: widget.itemId,
        mediaSourceId: _playbackInfo!.mediaSources.firstOrNull?.id ?? '',
        positionTicks: (_currentPosition * 10000000).round(),
        isPaused: !ref.read(isPlayingProvider),
      ));
    } catch (_) {}
  }
  
  Future<void> _reportStop() async {
    if (_playbackInfo == null) return;
    try {
      final api = ref.read(apiClientProvider);
      await api.playback.reportPlaybackStopped(PlaybackStopInfo(
        itemId: widget.itemId,
        mediaSourceId: _playbackInfo!.mediaSources.firstOrNull?.id ?? '',
        positionTicks: (_currentPosition * 10000000).round(),
      ));
    } catch (_) {}
  }
  
  @override
  void dispose() {
    _reportStop();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final isPlaying = ref.watch(isPlayingProvider);
    final volume = ref.watch(volumeProvider);
    final speed = ref.watch(playbackSpeedProvider);
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          if (!_isLocked) {
            setState(() => _showControls = !_showControls);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 视频区域（占位）
            Container(
              color: Colors.black,
              child: const Center(
                child: Icon(
                  Icons.play_circle_outline,
                  size: 80,
                  color: Colors.white30,
                ),
              ),
            ),
            
            // 控制层
            if (_showControls && !_isLocked)
              _buildControlsOverlay(isPlaying, volume, speed),
            
            // 锁定按钮（始终显示）
            if (_isLocked)
              Positioned(
                top: 40,
                left: 16,
                child: IconButton(
                  icon: const Icon(Icons.lock, color: Colors.white),
                  onPressed: () => setState(() => _isLocked = false),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildControlsOverlay(bool isPlaying, double volume, double speed) {
    return AnimatedOpacity(
      opacity: _showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        color: Colors.black.withValues(alpha: 0.4),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部栏
              _buildTopBar(),
              
              // 中间区域（手势区域）
              Expanded(
                child: Row(
                  children: [
                    // 左侧（截图/锁定）
                    SizedBox(
                      width: 60,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.camera_alt, color: Colors.white),
                            onPressed: () {},
                          ),
                          IconButton(
                            icon: Icon(_isLocked ? Icons.lock : Icons.lock_open, color: Colors.white),
                            onPressed: () => setState(() => _isLocked = !_isLocked),
                          ),
                        ],
                      ),
                    ),
                    
                    // 中间（双击区域）
                    Expanded(
                      child: GestureDetector(
                        onDoubleTap: () {
                          // 双击中间播放/暂停
                          ref.read(isPlayingProvider.notifier).state = !isPlaying;
                        },
                        child: Container(),
                      ),
                    ),
                    
                    // 右侧（倍速条）
                    SizedBox(
                      width: 60,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.add, color: Colors.white),
                            onPressed: () {
                              final newSpeed = (speed + 0.25).clamp(0.25, 4.0);
                              ref.read(playbackSpeedProvider.notifier).state = newSpeed;
                            },
                          ),
                          Text(
                            '${speed}x',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove, color: Colors.white),
                            onPressed: () {
                              final newSpeed = (speed - 0.25).clamp(0.25, 4.0);
                              ref.read(playbackSpeedProvider.notifier).state = newSpeed;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // 进度条
              _buildProgressBar(),
              
              // 底部控制栏
              _buildBottomBar(isPlaying),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => context.pop(),
          ),
          Expanded(
            child: Text(
              _itemInfo?.name ?? widget.itemId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.hd, color: Colors.white, size: 20),
            label: const Text('超分', style: TextStyle(color: Colors.white)),
          ),
          TextButton.icon(
            onPressed: () => _showSkipDialog(),
            icon: const Icon(Icons.skip_next, color: Colors.white, size: 20),
            label: const Text('跳过', style: TextStyle(color: Colors.white)),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () => _showMoreMenu(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildProgressBar() {
    final currentTime = _formatTime(_currentPosition);
    final remainingTime = _formatTime(_duration - _currentPosition);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() => _showRemaining = !_showRemaining),
            child: Text(
              _showRemaining ? '-$remainingTime' : currentTime,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
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
                value: _currentPosition,
                max: _duration,
                onChanged: (value) {
                  setState(() => _currentPosition = value);
                  _reportProgress();
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatTime(_duration),
            style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildBottomBar(bool isPlaying) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.skip_previous, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.replay_10, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 40,
            ),
            onPressed: () {
              ref.read(isPlayingProvider.notifier).state = !isPlaying;
            },
          ),
          IconButton(
            icon: const Icon(Icons.forward_10, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.skip_next, color: Colors.white),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
            onPressed: () => _showDanmakuSettings(),
          ),
          IconButton(
            icon: const Icon(Icons.subtitles, color: Colors.white),
            onPressed: () => _showSubtitleSettings(),
          ),
          IconButton(
            icon: const Icon(Icons.audiotrack, color: Colors.white),
            onPressed: () => _showAudioSettings(),
          ),
          IconButton(
            icon: const Icon(Icons.playlist_play, color: Colors.white),
            onPressed: () => _showEpisodeSelector(),
          ),
        ],
      ),
    );
  }
  
  String _formatTime(double seconds) {
    final hrs = (seconds ~/ 3600).toString().padLeft(2, '0');
    final mins = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toInt().toString().padLeft(2, '0');
    if (seconds >= 3600) {
      return '$hrs:$mins:$secs';
    }
    return '$mins:$secs';
  }
  
  void _showSkipDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('跳过片头'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTimeField('开始时间', '01:30'),
            const SizedBox(height: 12),
            _buildTimeField('结束时间', '03:15'),
            const SizedBox(height: 16),
            const Text('跳过模式'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'button', label: Text('显示按钮')),
                ButtonSegment(value: 'auto', label: Text('自动跳过')),
              ],
              selected: const {'button'},
              onSelectionChanged: (_) {},
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('保存')),
        ],
      ),
    );
  }
  
  Widget _buildTimeField(String label, String initialValue) {
    return Row(
      children: [
        Text(label),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: TextEditingController(text: initialValue),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.my_location),
            ),
          ),
        ),
      ],
    );
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
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.screen_rotation, color: Colors.white),
              title: const Text('旋转屏幕', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.timer, color: Colors.white),
              title: const Text('定时关闭', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.memory, color: Colors.white),
              title: const Text('内核切换', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.analytics, color: Colors.white),
              title: const Text('统计信息', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.aspect_ratio, color: Colors.white),
              title: const Text('画面比例', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
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
      builder: (context) => const _SubtitleSettingsSheet(),
    );
  }
  
  void _showAudioSettings() {
    showModalBottomSheet(
      context: context,
      builder: (context) => const _AudioSettingsSheet(),
    );
  }
  
  void _showEpisodeSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return _EpisodeSelectorSheet(scrollController: scrollController);
        },
      ),
    );
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
            title: const Text('中文繁體'),
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
class _SubtitleSettingsSheet extends StatelessWidget {
  const _SubtitleSettingsSheet();
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('字幕设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          const Text('字幕轨道'),
          ListTile(
            leading: const Icon(Icons.radio_button_checked),
            title: const Text('中文简体（默认）'),
            onTap: () {},
          ),
          const Divider(),
          const Text('字幕同步'),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.remove), onPressed: () {}),
              const Text('0.0s'),
              IconButton(icon: const Icon(Icons.add), onPressed: () {}),
            ],
          ),
        ],
      ),
    );
  }
}

/// 音频设置弹窗
class _AudioSettingsSheet extends StatelessWidget {
  const _AudioSettingsSheet();
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('音频设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          const Text('音频轨道'),
          ListTile(
            leading: const Icon(Icons.radio_button_checked),
            title: const Text('日语 5.1（默认）'),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.radio_button_unchecked),
            title: const Text('日语 2.0'),
            onTap: () {},
          ),
          const Divider(),
          const Text('音频同步'),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.remove), onPressed: () {}),
              const Text('0.0s'),
              IconButton(icon: const Icon(Icons.add), onPressed: () {}),
            ],
          ),
        ],
      ),
    );
  }
}

/// 选集弹窗
class _EpisodeSelectorSheet extends StatelessWidget {
  final ScrollController scrollController;
  
  const _EpisodeSelectorSheet({required this.scrollController});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 拖拽指示条
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('季度选择'),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: '第一季',
                items: const [
                  DropdownMenuItem(value: '第一季', child: Text('第一季')),
                  DropdownMenuItem(value: '第二季', child: Text('第二季')),
                ],
                onChanged: (_) {},
              ),
            ],
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: 12,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: Text('E${index + 1}'),
                  title: Text('第${index + 1}集'),
                  subtitle: const Text('25:30 · 1.2GB'),
                  trailing: index == 1
                      ? const Icon(Icons.check_circle, color: Color(0xFF5B8DEF))
                      : null,
                  onTap: () => Navigator.pop(context),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
