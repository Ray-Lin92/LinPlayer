import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_interfaces.dart';
import '../api/danmaku/danmaku_service.dart';
import '../providers/playback_providers.dart';
import '../utils/danmaku_matcher.dart';
import '../utils/danmaku_postprocess.dart';

/// 播放开始时自动匹配并加载弹幕（三端共用）。此前只有打开「搜索弹幕」面板才会
/// 匹配，用户得手动挑一次才显示；现在播放即自动挑可信度最高的一集弹幕直接显示。
///
/// 动漫专库弹弹Play 只在条目判定为动漫时放行（见 [MediaItem.isAnime] +
/// [DanmakuMatcher.resolveIsAnime]）；电视剧/电影只用自定义聚合源。
class DanmakuAutoLoader {
  /// 自动加载可信度阈值：低于此分不自动上屏，避免给非动漫/错配内容硬塞弹幕。
  /// ponytail: 命中率不佳再调；用户仍可手动搜索覆盖。
  static const double _minScore = 0.5;

  /// [api] 为空时（网盘/聚合直链等无 Emby 上下文）只按条目自身 genres 判定动漫。
  static Future<void> run(
    WidgetRef ref,
    ApiClientFactory? api,
    MediaItem item,
  ) async {
    try {
      if (!ref.read(danmakuEnabledProvider)) return;
      // 已有弹幕（用户手动加载 / 上一次残留）不覆盖。
      if (ref.read(loadedDanmakuProvider).isNotEmpty) return;

      final service = ref.read(danmakuServiceProvider);
      final allowOfficial = await DanmakuMatcher.resolveIsAnime(
        item,
        fetchItem: api == null ? null : (id) => api.media.getItemDetails(id),
      );
      final candidates = await DanmakuMatcher.matchAll(
        service,
        item,
        allowOfficial: allowOfficial,
      );
      if (candidates.isEmpty || candidates.first.score < _minScore) return;

      final best = candidates.first;
      var items = await service.getComments(best.episodeId,
          sourceId: best.sourceId);
      items = applyDanmakuFilterAndDedup(
        items,
        blockwords: ref.read(danmakuBlockwordsProvider),
        dedup: ref.read(danmakuDedupProvider),
        dedupWindow: ref.read(danmakuDedupWindowProvider),
      );
      if (items.isEmpty) return;

      // 期间用户可能切集/手动加载/关弹幕——再校验一次才上屏。
      if (!ref.read(danmakuEnabledProvider)) return;
      if (ref.read(loadedDanmakuProvider).isNotEmpty) return;
      ref.read(loadedDanmakuProvider.notifier).state = items;
    } catch (_) {
      // 自动加载失败静默，用户仍可手动搜索。
    }
  }
}
