import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';

/// 侧边栏是否收起（三端外壳共用，由标题栏的汉堡按钮切换）。
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

/// 沉浸模式：播放页进入真正全屏时置 true，应用根据此隐藏自绘标题栏 [AppTitleBar]。
///
/// Windows/Linux 隐藏了系统标题栏、改由 Flutter 自绘标题栏（见 desktop_window_chrome.dart）。
/// 该自绘标题栏渲染在路由内容之上，因此即便原生窗口已无边框全屏，标题栏仍会留在画面顶部。
/// 播放页全屏时通过本 Provider 通知应用根隐藏标题栏，实现真正的全屏。
final desktopImmersiveModeProvider = StateProvider<bool>((ref) => false);

/// 桌面端主导航项（三种外壳共用）。
class DesktopNavItem {
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const DesktopNavItem({
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

const desktopNavItems = <DesktopNavItem>[
  DesktopNavItem(
    path: '/',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    label: '首页',
  ),
  DesktopNavItem(
    path: '/libraries',
    icon: Icons.collections_bookmark_outlined,
    selectedIcon: Icons.collections_bookmark_rounded,
    label: '媒体库',
  ),
  DesktopNavItem(
    path: '/favorites',
    icon: Icons.favorite_outline_rounded,
    selectedIcon: Icons.favorite_rounded,
    label: '收藏',
  ),
  DesktopNavItem(
    path: '/downloads',
    icon: Icons.download_outlined,
    selectedIcon: Icons.download_rounded,
    label: '下载',
  ),
  DesktopNavItem(
    path: '/servers',
    icon: Icons.dns_outlined,
    selectedIcon: Icons.dns_rounded,
    label: '服务器',
  ),
  DesktopNavItem(
    path: '/settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    label: '设置',
  ),
  // 排行榜：分支 index 恒为末位（隐藏时不影响前序索引），但展示位置由
  // [desktopVisibleNav] 排到「收藏」之后，观感更自然。
  DesktopNavItem(
    path: '/rankings',
    icon: Icons.leaderboard_outlined,
    selectedIcon: Icons.leaderboard_rounded,
    label: '排行榜',
  ),
];

/// 排行榜分支在 [desktopNavItems] / 路由分支中的固定索引（末位）。
final int desktopRankingBranchIndex =
    desktopNavItems.indexWhere((e) => e.path == '/rankings');

/// 计算侧边栏可见导航项（含真实分支索引）。排行榜按开关显隐，且展示在「收藏」后。
/// 返回的 branchIndex 用于 [StatefulNavigationShell.goBranch] 与选中态比较。
List<({int branchIndex, DesktopNavItem item})> desktopVisibleNav(
    bool rankingEnabled) {
  // 展示顺序：首页/媒体库/收藏/(排行榜)/下载/服务器/设置。
  final order = <int>[0, 1, 2];
  if (rankingEnabled) order.add(desktopRankingBranchIndex);
  order.addAll([3, 4, 5]);
  return [
    for (final i in order) (branchIndex: i, item: desktopNavItems[i]),
  ];
}

/// 由当前路由计算选中的导航索引（首页聚合 /home 与续播页）。
int desktopSelectedNavIndex(String currentPath) {
  for (var i = 0; i < desktopNavItems.length; i++) {
    final item = desktopNavItems[i];
    final selected = currentPath == item.path ||
        (item.path == '/' &&
            (currentPath == '/home' || currentPath == resumeRoutePath));
    if (selected) return i;
  }
  return 0;
}
