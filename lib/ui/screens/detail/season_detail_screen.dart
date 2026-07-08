import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api/api_interfaces.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/media_providers.dart';

/// 季详情页
class SeasonDetailScreen extends ConsumerWidget {
  final String seasonId;
  
  const SeasonDetailScreen({super.key, required this.seasonId});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodesAsync = ref.watch(episodesProvider((seriesId: 'series_$seasonId', seasonId: seasonId)));
    final api = ref.read(apiClientProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('季详情'),
      ),
      body: episodesAsync.when(
        data: (episodes) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: episodes.length,
            itemBuilder: (context, index) {
              final episode = episodes[index];
              final imageUrl = episode.primaryImageTag != null
                  ? api.image.getPrimaryImageUrl(episode.id, tag: episode.primaryImageTag, maxWidth: 200)
                  : null;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  onTap: () => context.push('/player/${episode.id}'),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 100,
                      height: 60,
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: imageUrl != null
                          ? Image.network(imageUrl, fit: BoxFit.cover)
                          : const Center(child: Icon(Icons.play_arrow)),
                    ),
                  ),
                  title: Text('E${episode.indexNumber} ${episode.name}'),
                  subtitle: Text(
                    episode.formattedRuntime ?? '',
                    style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
                  ),
                  trailing: episode.userData?.played ?? false
                      ? const Icon(Icons.check_circle, color: Color(0xFF5B8DEF))
                      : null,
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('错误: $error')),
      ),
    );
  }
}

/// 集详情页（电影/单集通用播放准备页）
class EpisodeDetailScreen extends ConsumerWidget {
  final String episodeId;
  
  const EpisodeDetailScreen({super.key, required this.episodeId});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackAsync = ref.watch(playbackInfoProvider(episodeId));
    final server = ref.watch(currentServerProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('播放选项'),
      ),
      body: playbackAsync.when(
        data: (info) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDropdownTile(
                context,
                icon: Icons.route,
                title: '线路选择',
                value: server?.activeLineUrl ?? '当前线路',
                onTap: () => _showLineSelector(context, ref),
              ),
              if (info.mediaSources.length > 1)
                _buildDropdownTile(
                  context,
                  icon: Icons.layers,
                  title: '版本选择',
                  value: info.mediaSources.first.name ?? '默认',
                  onTap: () => _showSourceSelector(context, info),
                ),
              Builder(builder: (ctx) {
                final audio = info.mediaSources.firstOrNull?.mediaStreams.where((s) => s.isAudio).firstOrNull;
                return _buildDropdownTile(
                  ctx,
                  icon: Icons.audiotrack,
                  title: '音频选择',
                  value: audio?.displayTitle ?? '默认音轨',
                  onTap: () => _showStreamSelector(context, info, 'Audio'),
                );
              }),
              Builder(builder: (ctx) {
                final sub = info.mediaSources.firstOrNull?.mediaStreams.where((s) => s.isSubtitle).firstOrNull;
                return _buildDropdownTile(
                  ctx,
                  icon: Icons.subtitles,
                  title: '字幕选择',
                  value: sub?.displayTitle ?? '无字幕',
                  onTap: () => _showStreamSelector(context, info, 'Subtitle'),
                );
              }),
              _buildDropdownTile(
                context,
                icon: Icons.subtitles_outlined,
                title: '次字幕选择',
                value: '无',
                onTap: () {},
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.push('/player/$episodeId'),
                icon: const Icon(Icons.play_arrow),
                label: const Text('开始播放'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('加载播放信息失败')),
      ),
    );
  }
  
  void _showLineSelector(BuildContext context, WidgetRef ref) {
    final server = ref.read(currentServerProvider);
    if (server == null) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: server.lines.asMap().entries.map((entry) {
            final idx = entry.key;
            final line = entry.value;
            return ListTile(
              title: Text(line.name),
              subtitle: Text(line.url),
              trailing: idx == server.activeLineIndex ? const Icon(Icons.check, color: Color(0xFF5B8DEF)) : null,
              onTap: () {
                ref.read(serverListProvider.notifier).setActiveLine(server.id, idx);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
  
  void _showSourceSelector(BuildContext context, PlaybackInfo info) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: info.mediaSources.map((source) {
            return ListTile(
              title: Text(source.name ?? '默认'),
              subtitle: Text(source.container ?? ''),
              onTap: () => Navigator.pop(ctx),
            );
          }).toList(),
        ),
      ),
    );
  }
  
  void _showStreamSelector(BuildContext context, PlaybackInfo info, String type) {
    final streams = info.mediaSources.firstOrNull?.mediaStreams.where((s) => s.type == type).toList() ?? [];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    type == 'Audio' ? '选择音频轨道' : '选择字幕轨道',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (streams.isEmpty)
              const ListTile(title: Text('无可用轨道'))
            else
              ...streams.map((stream) {
                return ListTile(
                  title: Text(stream.displayTitle ?? stream.language ?? '轨道 ${stream.index}'),
                  subtitle: stream.codec != null ? Text('编码: ${stream.codec}') : null,
                  trailing: stream.isDefault == true
                      ? const Icon(Icons.check, color: Color(0xFF5B8DEF))
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('已选择: ${stream.displayTitle ?? stream.language ?? '轨道 ${stream.index}'}')),
                    );
                  },
                );
              }),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDropdownTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
