import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/api/api_interfaces.dart';
import '../../../core/providers/media_providers.dart';
import '../../widgets/common/media_widgets.dart';

/// 首页
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentServer = ref.watch(currentServerProvider);
    
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 顶部栏
          SliverToBoxAdapter(
            child: _HomeAppBar(serverName: currentServer?.name ?? '服务器'),
          ),
          
          // 随机推荐轮播
          const SliverToBoxAdapter(child: RandomRecommendationCarousel()),
          
          // 继续观看
          const SliverToBoxAdapter(child: ContinueWatchingSection()),
          
          // 媒体库
          const SliverToBoxAdapter(child: LibrariesSection()),
          
          // 各媒体库最新内容
          const SliverToBoxAdapter(child: LatestItemsSections()),
          
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ],
      ),
    );
  }
}

/// 首页顶部栏
class _HomeAppBar extends StatelessWidget {
  final String serverName;
  
  const _HomeAppBar({required this.serverName});
  
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 服务器名称
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF5B8DEF).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.dns, size: 18, color: Color(0xFF5B8DEF)),
                ),
                const SizedBox(width: 8),
                Text(
                  serverName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const Spacer(),
            // 媒体库按钮
            IconButton(
              icon: const Icon(Icons.collections_bookmark),
              onPressed: () {
                // 跳转到媒体库页
              },
            ),
            // 搜索按钮
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                context.push('/search');
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 随机推荐轮播
class RandomRecommendationCarousel extends ConsumerStatefulWidget {
  const RandomRecommendationCarousel({super.key});
  
  @override
  ConsumerState<RandomRecommendationCarousel> createState() => _RandomRecommendationCarouselState();
}

class _RandomRecommendationCarouselState extends ConsumerState<RandomRecommendationCarousel> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  
  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final recommendationsAsync = ref.watch(randomRecommendationsProvider);
    final screenHeight = MediaQuery.of(context).size.height;
    final carouselHeight = screenHeight * 0.6;
    
    return recommendationsAsync.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        
        return SizedBox(
          height: carouselHeight,
          child: Stack(
            children: [
              // 轮播内容
              PageView.builder(
                controller: _pageController,
                itemCount: items.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _CarouselItem(
                    item: item,
                    onTap: () => context.push('/detail/${item.id}'),
                  );
                },
              ),
              
              // 底部渐变
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8),
                        Theme.of(context).scaffoldBackgroundColor,
                      ],
                    ),
                  ),
                ),
              ),
              
              // 指示器
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(items.length, (index) {
                    return Container(
                      width: index == _currentPage ? 20 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: index == _currentPage
                            ? const Color(0xFF5B8DEF)
                            : Colors.white.withValues(alpha: 0.5),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => SizedBox(
        height: carouselHeight,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _CarouselItem extends ConsumerWidget {
  final MediaItem item;
  final VoidCallback onTap;
  
  const _CarouselItem({required this.item, required this.onTap});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiClientProvider);
    final imageUrl = item.backdropImageTag != null
        ? api.image.getBackdropImageUrl(item.id, tag: item.backdropImageTag, maxWidth: 800)
        : item.primaryImageTag != null
            ? api.image.getPrimaryImageUrl(item.id, tag: item.primaryImageTag, maxWidth: 800)
            : null;
    
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          MediaImage(
            imageUrl: imageUrl,
            width: double.infinity,
            height: double.infinity,
          ),
          
          // 底部信息
          Positioned(
            bottom: 40,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    shadows: [
                      Shadow(blurRadius: 8, color: Colors.black54),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (item.communityRating != null) ...[
                      const Icon(Icons.star, size: 18, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        item.communityRating!.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    ...?item.genres?.take(5).map((genre) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          genre,
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                        ),
                      ),
                    )),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 继续观看区块
class ContinueWatchingSection extends ConsumerWidget {
  const ContinueWatchingSection({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumeAsync = ref.watch(resumeItemsProvider);
    
    return resumeAsync.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: '继续观看',
              onMoreTap: () {},
            ),
            HorizontalList(
              height: 180,
              children: items.where((item) => !(item.userData?.played ?? false)).map((item) {
                return SizedBox(
                  width: 280,
                  child: _ContinueWatchingCard(item: item),
                );
              }).toList(),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _ContinueWatchingCard extends ConsumerWidget {
  final MediaItem item;
  
  const _ContinueWatchingCard({required this.item});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiClientProvider);
    final imageUrl = item.primaryImageTag != null
        ? api.image.getPrimaryImageUrl(item.id, tag: item.primaryImageTag, maxWidth: 300)
        : null;
    
    return GestureDetector(
      onTap: () {
        if (item.type == 'Episode' && item.seriesId != null) {
          context.push('/detail/${item.seriesId}');
        } else {
          context.push('/detail/${item.id}');
        }
      },
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            MediaImage(
              imageUrl: imageUrl,
              width: 120,
              height: 180,
            ),
            // 右侧信息
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (item.seriesName != null)
                      Text(
                        '${item.seriesName} · S${item.parentIndexNumber}E${item.indexNumber}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    const SizedBox(height: 12),
                    // 进度条
                    if (item.progress != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: item.progress,
                              backgroundColor: Colors.grey.shade300,
                              valueColor: const AlwaysStoppedAnimation(Color(0xFF5B8DEF)),
                              minHeight: 4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(item.progress! * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 媒体库区块
class LibrariesSection extends ConsumerWidget {
  const LibrariesSection({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final librariesAsync = ref.watch(librariesProvider);
    
    return librariesAsync.when(
      data: (libraries) {
        if (libraries.isEmpty) return const SizedBox.shrink();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(title: '媒体库'),
            HorizontalList(
              height: 140,
              children: libraries.map((library) {
                return SizedBox(
                  width: 140,
                  child: GestureDetector(
                    onTap: () => context.push('/library/${library.id}'),
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF5B8DEF).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Icon(
                                library.collectionType == 'movies'
                                    ? Icons.movie
                                    : Icons.tv,
                                size: 40,
                                color: const Color(0xFF5B8DEF),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          library.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// 各媒体库最新内容区块
class LatestItemsSections extends ConsumerWidget {
  const LatestItemsSections({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final librariesAsync = ref.watch(librariesProvider);
    
    return librariesAsync.when(
      data: (libraries) {
        return Column(
          children: libraries.map((library) {
            return _LibraryLatestSection(library: library);
          }).toList(),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _LibraryLatestSection extends ConsumerWidget {
  final Library library;
  
  const _LibraryLatestSection({required this.library});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestAsync = ref.watch(latestItemsProvider(library.id));
    
    return latestAsync.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: library.name,
              onMoreTap: () => context.push('/library/${library.id}'),
            ),
            HorizontalList(
              height: 200,
              children: items.map((item) {
                return SizedBox(
                  width: 120,
                  child: MediaPoster(
                    item: item,
                    width: 120,
                    height: 160,
                    onTap: () => context.push('/detail/${item.id}'),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
