import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'core/services/app_logger.dart';
import 'core/services/cache_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MediaKit.ensureInitialized();
  log.i('Main', 'media_kit 初始化完成');

  CacheService.configureMemoryCache();

  // 配置 ExtendedImage 缓存参数
  ExtendedImage.globalStateWidgetBuilder = (context, state) {
    if (state.extendedImageLoadState == LoadState.loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
      return const SizedBox.shrink();
  };

  runApp(
    const ProviderScope(
      child: LinPlayerApp(),
    ),
  );
}
