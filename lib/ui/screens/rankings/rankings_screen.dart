import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/ranking/ranking_models.dart';
import '../../../core/providers/media_providers.dart';
import '../../../core/providers/ranking_providers.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/widgets/app_shimmer.dart';
import '../../utils/media_helpers.dart';
import '../../widgets/common/media_widgets.dart';

/// 移动端排行榜页（Material 风格）：顶部一级分组 + 子类胶囊，下方名次列表。
/// 前三名金/银/铜大号名次，下拉刷新，点按看详情。
class RankingsScreen extends ConsumerStatefulWidget {
  const RankingsScreen({super.key});

  @override
  ConsumerState<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends ConsumerState<RankingsScreen> {
  RankingGroup? _group;
  String? _categoryId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = ref.watch(rankingGroupsProvider);

    if (groups.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('排行榜')),
        body: const _EmptyState(
          icon: Icons.leaderboard_outlined,
          text: '当前版本未配置排行榜数据源',
        ),
      );
    }

    final group = groups.contains(_group) ? _group! : groups.first;
    final categories = ref.watch(rankingCategoriesProvider(group));
    final categoryId = categories.any((c) => c.id == _categoryId)
        ? _categoryId!
        : (categories.isNotEmpty ? categories.first.id : '');

    return Scaffold(
      appBar: AppBar(
        title: const Text('排行榜'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              _GroupBar(
                groups: groups,
                selected: group,
                onSelect: (g) => setState(() {
                  _group = g;
                  _categoryId = null;
                }),
              ),
              _CategoryBar(
                categories: categories,
                selectedId: categoryId,
                onSelect: (id) => setState(() => _categoryId = id),
              ),
            ],
          ),
        ),
      ),
      body: categoryId.isEmpty
          ? const _EmptyState(
              icon: Icons.inbox_outlined, text: '暂无榜单')
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(rankingListProvider(categoryId));
                await ref.read(rankingListProvider(categoryId).future);
              },
              child: _RankingList(categoryId: categoryId, theme: theme),
            ),
    );
  }
}

class _GroupBar extends StatelessWidget {
  const _GroupBar({
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  final List<RankingGroup> groups;
  final RankingGroup selected;
  final ValueChanged<RankingGroup> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: GestureDetector(
                onTap: () => onSelect(g),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: g == selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    g.label,
                    style: TextStyle(
                      color: g == selected
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  final List<RankingCategory> categories;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final c in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c.label),
                selected: c.id == selectedId,
                onSelected: (_) => onSelect(c.id),
                labelStyle: TextStyle(
                  fontSize: 13,
                  color: c.id == selectedId
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurface,
                ),
                selectedColor: theme.colorScheme.primary,
                showCheckmark: false,
              ),
            ),
        ],
      ),
    );
  }
}

class _RankingList extends ConsumerWidget {
  const _RankingList({required this.categoryId, required this.theme});

  final String categoryId;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rankingListProvider(categoryId));
    return async.when(
      loading: () => ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: 8,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: _SkeletonRow(),
        ),
      ),
      error: (e, _) => const _EmptyState(
        icon: Icons.wifi_off_rounded,
        text: '加载失败，下拉重试',
      ),
      data: (items) {
        if (items.isEmpty) {
          return const _EmptyState(icon: Icons.inbox_outlined, text: '暂无数据');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final e = items[index];
            return _RankRow(entry: e).appEntrance(index: index);
          },
        );
      },
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.entry});

  final RankingEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showEntrySheet(context, entry),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Align(
                alignment: Alignment.centerRight,
                child: _RankNumber(rank: entry.rank),
              ),
            ),
            const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MediaImage(
                imageUrl: entry.imageUrl,
                width: 64,
                height: 90,
                fit: BoxFit.cover,
                cacheWidth: 180,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if ((entry.subtitle ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (entry.rating != null && entry.rating! > 0) ...[
              const SizedBox(width: 8),
              _RatingChip(rating: entry.rating!),
            ],
          ],
        ),
      ),
    );
  }
}

class _RankNumber extends StatelessWidget {
  const _RankNumber({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final color = rankAccentColor(rank);
    return Text(
      '$rank',
      textAlign: TextAlign.right,
      style: TextStyle(
        fontSize: rank <= 3 ? 18 : 15,
        fontWeight: FontWeight.w800,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB300).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFB300)),
          const SizedBox(width: 2),
          Text(
            rating.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFFFFA000),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 40),
        ShimmerBox(width: 64, height: 90, borderRadius: BorderRadius.circular(8)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerBox(
                  width: 160, height: 14, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 8),
              ShimmerBox(
                  width: 90, height: 12, borderRadius: BorderRadius.circular(4)),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.28),
        Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Center(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// 前三名金/银/铜；其余返回 null（用默认色）。三端共用。
Color? rankAccentColor(int rank) => switch (rank) {
      1 => const Color(0xFFFFC107),
      2 => const Color(0xFFB0BEC5),
      3 => const Color(0xFFCD7F32),
      _ => null,
    };

/// 点按榜单条目：在所有已登录服务器里搜同名资源，按服务器分组展示集数/画质，
/// 点某台即切到该服务器并打开对应结果。
void _showEntrySheet(BuildContext context, RankingEntry entry) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _EntrySheet(entry: entry),
  );
}

class _EntrySheet extends ConsumerWidget {
  const _EntrySheet({required this.entry});

  final RankingEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(rankingCrossServerMatchProvider(entry.title));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '在已登录服务器中查找',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text('搜索失败，请稍后重试',
                    style: theme.textTheme.bodyMedium),
              ),
            ),
            data: (matches) {
              if (matches.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: Text('未在任何服务器找到')),
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final m in matches) _ServerMatchRow(match: m),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ServerMatchRow extends ConsumerWidget {
  const _ServerMatchRow({required this.match});

  final ServerMatchInfo match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final api = apiClientForItem(ref, match.item);
    final urls = resolveMediaItemImageUrls(api, match.item, maxWidth: 180);
    final epLabel =
        match.episodeCount != null ? '共 ${match.episodeCount} 集' : '集数 —';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.of(context).pop();
        openMediaItem(ref, context, match.item);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: MediaImage(
                imageUrl: urls.isNotEmpty ? urls.first : null,
                imageUrls: urls.length > 1 ? urls.sublist(1) : null,
                width: 48,
                height: 68,
                fit: BoxFit.cover,
                cacheWidth: 140,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.serverName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _tag(theme, epLabel, null),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

Widget _tag(ThemeData theme, String text, Color? color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (color ?? theme.colorScheme.surfaceContainerHighest)
            .withValues(alpha: color == null ? 0.6 : 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color ?? theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
