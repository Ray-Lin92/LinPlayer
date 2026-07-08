part of 'desktop_player_screen.dart';

class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _MarqueeText({required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
  }

  @override
  void didUpdateWidget(_MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _controller.stop();
      _controller.reset();
      _needsScroll = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _checkOverflow(BoxConstraints constraints) {
    final textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: double.infinity);
    _needsScroll = textPainter.width > constraints.maxWidth;
    if (_needsScroll && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!_needsScroll && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _checkOverflow(constraints);
        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              if (!_needsScroll) return child!;
              final textPainter = TextPainter(
                text: TextSpan(text: widget.text, style: widget.style),
                textDirection: TextDirection.ltr,
              );
              textPainter.layout(maxWidth: double.infinity);
              final offset = (textPainter.width - constraints.maxWidth) *
                  _controller.value;
              return Transform.translate(
                offset: Offset(-offset, 0),
                child: child,
              );
            },
            child: Text(widget.text,
                style: widget.style, overflow: TextOverflow.ellipsis),
          ),
        );
      },
    );
  }
}

class _Anime4KLevelDialog extends StatelessWidget {
  final String currentLevel;

  const _Anime4KLevelDialog({required this.currentLevel});

  static const List<Map<String, String>> levels = [
    {'value': 'off', 'label': '关闭'},
    {'value': 'modeA', 'label': '模式 A - 性能优先'},
    {'value': 'modeB', 'label': '模式 B - 平衡'},
    {'value': 'modeC', 'label': '模式 C - 质量优先'},
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Anime4K 超分设置',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
            const Divider(color: Colors.white12, height: 1),
            ...levels.map((level) => ListTile(
                  title: Text(level['label']!,
                      style: const TextStyle(color: Colors.white)),
                  trailing: currentLevel == level['value']
                      ? const Icon(Icons.check, color: Color(0xFF5B8DEF))
                      : null,
                  onTap: () => Navigator.pop(context, level['value']),
                )),
          ],
        ),
      ),
    );
  }
}

class _MoreMenuSheet extends StatelessWidget {
  final VoidCallback onShowAspectRatio;
  final VoidCallback onTakeScreenshot;
  final VoidCallback onShowSubtitleSelector;
  final VoidCallback onShowAudioSelector;
  final VoidCallback? onShowEpisodeSelector;
  final VoidCallback onToggleHardwareDecoding;
  final VoidCallback onToggleStats;
  final VoidCallback onToggleFullscreen;
  final VoidCallback? onShowAnime4K;
  final bool isStatsVisible;
  final bool isFullscreen;
  final bool hardwareDecodingEnabled;
  final String? anime4KLabel;

  const _MoreMenuSheet({
    required this.onShowAspectRatio,
    required this.onTakeScreenshot,
    required this.onShowSubtitleSelector,
    required this.onShowAudioSelector,
    required this.onShowEpisodeSelector,
    required this.onToggleHardwareDecoding,
    required this.onToggleStats,
    required this.onToggleFullscreen,
    required this.onShowAnime4K,
    required this.isStatsVisible,
    required this.isFullscreen,
    required this.hardwareDecodingEnabled,
    required this.anime4KLabel,
  });

  @override
  Widget build(BuildContext context) {
    void handleAction(VoidCallback action) {
      Navigator.pop(context);
      action();
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined, color: Colors.white),
            title: const Text('截图', style: TextStyle(color: Colors.white)),
            onTap: () => handleAction(onTakeScreenshot),
          ),
          ListTile(
            leading: const Icon(Icons.subtitles, color: Colors.white),
            title: const Text('字幕选择', style: TextStyle(color: Colors.white)),
            onTap: () => handleAction(onShowSubtitleSelector),
          ),
          ListTile(
            leading: const Icon(Icons.audiotrack, color: Colors.white),
            title: const Text('音轨选择', style: TextStyle(color: Colors.white)),
            onTap: () => handleAction(onShowAudioSelector),
          ),
          if (onShowEpisodeSelector != null)
            ListTile(
              leading: const Icon(Icons.playlist_play, color: Colors.white),
              title: const Text('选集', style: TextStyle(color: Colors.white)),
              onTap: () => handleAction(onShowEpisodeSelector!),
            ),
          ListTile(
            leading: const Icon(Icons.aspect_ratio, color: Colors.white),
            title: const Text('画面比例', style: TextStyle(color: Colors.white)),
            onTap: () {
              handleAction(onShowAspectRatio);
            },
          ),
          ListTile(
            leading: Icon(
              hardwareDecodingEnabled ? Icons.memory : Icons.slow_motion_video,
              color: Colors.white,
            ),
            title: const Text('硬件解码', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              hardwareDecodingEnabled ? '当前已开启' : '当前已关闭',
              style: const TextStyle(color: Colors.white54),
            ),
            onTap: () => handleAction(onToggleHardwareDecoding),
          ),
          if (onShowAnime4K != null)
            ListTile(
              leading: const Icon(Icons.hd, color: Colors.white),
              title: const Text('Anime4K 超分',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text(
                anime4KLabel == null || anime4KLabel == 'off'
                    ? '当前已关闭'
                    : '当前模式: $anime4KLabel',
                style: const TextStyle(color: Colors.white54),
              ),
              onTap: () => handleAction(onShowAnime4K!),
            ),
          ListTile(
            leading: const Icon(Icons.analytics, color: Colors.white),
            title: const Text('统计信息', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              isStatsVisible ? '当前显示中' : '当前已隐藏',
              style: const TextStyle(color: Colors.white54),
            ),
            onTap: () => handleAction(onToggleStats),
          ),
          ListTile(
            leading: Icon(
              isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white,
            ),
            title: Text(
              isFullscreen ? '退出全屏' : '进入全屏',
              style: const TextStyle(color: Colors.white),
            ),
            onTap: () => handleAction(onToggleFullscreen),
          ),
        ],
      ),
    );
  }
}

class _EpisodeSelectorDialog extends ConsumerWidget {
  final String seriesId;
  final String currentEpisodeId;
  final String? currentMediaSourceId;

  const _EpisodeSelectorDialog({
    required this.seriesId,
    required this.currentEpisodeId,
    this.currentMediaSourceId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodesAsync =
        ref.watch(episodesProvider((seriesId: seriesId, seasonId: null)));

    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text('选集',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Flexible(
              child: DesktopSmoothScrollBuilder(
                builder: (context, controller) => episodesAsync.when(
                  data: (episodes) => ListView.builder(
                    controller: controller,
                    itemCount: episodes.length,
                    itemBuilder: (context, index) {
                      final episode = episodes[index];
                      final isCurrent = episode.id == currentEpisodeId;
                      return ListTile(
                        title: Text(
                          '第 ${episode.indexNumber ?? index + 1} 集: ${episode.name}',
                          style: TextStyle(
                            color: isCurrent
                                ? const Color(0xFF5B8DEF)
                                : Colors.white,
                            fontWeight:
                                isCurrent ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        trailing: isCurrent
                            ? const Icon(Icons.play_arrow,
                                color: Color(0xFF5B8DEF))
                            : null,
                        onTap: () {
                          if (!isCurrent) {
                            context.replace(
                              '/player/${episode.id}'
                              '${currentMediaSourceId != null ? '?mediaSourceId=$currentMediaSourceId' : ''}',
                            );
                          }
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Text('加载失败: $error',
                        style: const TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkipTimeField extends ConsumerWidget {
  final String label;
  final StateProvider<int> provider;

  const _SkipTimeField({required this.label, required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(provider);
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        Expanded(
          flex: 3,
          child: TextFormField(
            initialValue: value.toString(),
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.1),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (text) {
              final val = int.tryParse(text);
              if (val != null && val >= 0) {
                ref.read(provider.notifier).state = val;
              }
            },
          ),
        ),
      ],
    );
  }
}
