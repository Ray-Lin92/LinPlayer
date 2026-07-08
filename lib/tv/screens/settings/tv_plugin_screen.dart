import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../plugins/manager/plugin_manager.dart';
import '../../../plugins/models/plugin_info.dart';
import '../../../plugins/store/plugin_store.dart';
import '../../../plugins/ui/plugin_permission_dialog.dart';
import '../../theme/tv_design_tokens.dart';
import '../../theme/tv_metrics.dart';
import '../../widgets/tv_focusable.dart';
import '../../widgets/tv_toast.dart';

/// TV 端「插件」面板（遥控器友好）。
///
/// 苹果/TV 都无法用文件选择器导入 .ipk，故 TV 端走插件市场网络安装：从仓库
/// 列出适配 TV 的插件，遥控器选中即装，无需打字。下方列出已安装插件，可启用/
/// 禁用/卸载。与移动/桌面共用宿主 [PluginManager]。
class TvPluginScreen extends ConsumerStatefulWidget {
  const TvPluginScreen({super.key});

  @override
  ConsumerState<TvPluginScreen> createState() => _TvPluginScreenState();
}

class _TvPluginScreenState extends ConsumerState<TvPluginScreen> {
  final PluginManager _manager = PluginManager.instance;
  late Future<List<StorePlugin>> _store;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _store = PluginStore.fetchRegistry();
    _manager.addListener(_onChange);
  }

  @override
  void dispose() {
    _manager.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _reloadStore() {
    setState(() => _store = PluginStore.fetchRegistry());
  }

  Future<void> _install(StorePlugin plugin) async {
    final url = plugin.packageUrl;
    if (url == null) return;
    setState(() => _busy.add(plugin.id));
    try {
      final info = await _manager.installFromUrl(url);
      if (mounted) TvToast.show(context, '已安装「${info.name}」，在下方启用');
    } catch (e) {
      if (mounted) TvToast.show(context, '安装失败: $e');
    } finally {
      if (mounted) setState(() => _busy.remove(plugin.id));
    }
  }

  Future<void> _toggle(PluginInfo info, bool enable) async {
    if (enable) {
      final agreed = await showPluginPermissionConsent(context, info.manifest);
      if (!agreed) return;
      try {
        await _manager.enable(info.id);
        if (mounted) TvToast.show(context, '已启用「${info.name}」');
      } catch (e) {
        if (mounted) TvToast.show(context, '启用失败: $e');
      }
    } else {
      await _manager.disable(info.id);
      if (mounted) TvToast.show(context, '已禁用「${info.name}」');
    }
  }

  Future<void> _uninstall(PluginInfo info) async {
    await _manager.uninstall(info.id);
    if (mounted) TvToast.show(context, '已卸载「${info.name}」');
  }

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    final installed = _manager.plugins;
    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(m.spacingXl),
          children: [
            Text('插件',
                style: TextStyle(
                    fontSize: m.fontSizeXxl,
                    color: TvDesignTokens.textPrimary,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: m.spacingMd),
            _intro(m),
            SizedBox(height: m.spacingLg),
            _sectionTitle(m, '已安装'),
            if (installed.isEmpty)
              _hint(m, '还没有安装任何插件，从下方插件市场选择安装。')
            else
              for (final info in installed) _installedRow(m, info),
            SizedBox(height: m.spacingLg),
            Row(
              children: [
                Expanded(child: _sectionTitle(m, '插件市场')),
                _miniAction(m, Icons.refresh, _reloadStore),
              ],
            ),
            _storeList(m),
          ],
        ),
      ),
    );
  }

  Widget _storeList(TvMetrics m) {
    return FutureBuilder<List<StorePlugin>>(
      future: _store,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: m.spacingXl),
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return _hint(m, '加载插件市场失败：${snap.error}');
        }
        final list = (snap.data ?? const [])
            .where((p) => p.packageUrl != null && p.supports('tv'))
            .toList(growable: false);
        if (list.isEmpty) {
          return _hint(m, '仓库暂无适配 TV 的插件。');
        }
        return Column(children: [for (final p in list) _storeRow(m, p)]);
      },
    );
  }

  Widget _storeRow(TvMetrics m, StorePlugin plugin) {
    final installed = _manager.pluginById(plugin.id);
    final busy = _busy.contains(plugin.id);
    final sameVersion =
        installed != null && installed.version == plugin.version;
    final String trailingText;
    if (busy) {
      trailingText = '安装中…';
    } else if (sameVersion) {
      trailingText = '已安装';
    } else if (installed != null) {
      trailingText = '更新 v${plugin.version}';
    } else {
      trailingText = '安装';
    }
    return _card(
      m,
      title: plugin.name,
      subtitle: plugin.description,
      enabled: !busy && !sameVersion,
      trailing: busy
          ? SizedBox(
              width: m.s(22),
              height: m.s(22),
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(trailingText,
              style: TextStyle(
                  fontSize: m.fontSizeSm,
                  color: sameVersion
                      ? TvDesignTokens.textSecondary
                      : TvDesignTokens.brand)),
      onSelect: (busy || sameVersion) ? null : () => _install(plugin),
    );
  }

  Widget _installedRow(TvMetrics m, PluginInfo info) {
    final loading = info.status == PluginStatus.loading;
    return _card(
      m,
      title: info.name,
      subtitle:
          'v${info.version} · ${info.manifest.author}${info.faulted ? ' · 已自动禁用' : ''}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            SizedBox(
              width: m.s(22),
              height: m.s(22),
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Text(info.isEnabled ? '已启用' : '已禁用',
                style: TextStyle(
                    fontSize: m.fontSizeSm,
                    color: info.isEnabled
                        ? TvDesignTokens.brand
                        : TvDesignTokens.textSecondary)),
          SizedBox(width: m.spacingMd),
          _miniAction(m, Icons.delete_outline, () => _uninstall(info),
              color: Colors.redAccent),
        ],
      ),
      onSelect: loading ? null : () => _toggle(info, !info.isEnabled),
    );
  }

  // ===== TV 焦点向控件 =====

  Widget _sectionTitle(TvMetrics m, String text) => Padding(
        padding: EdgeInsets.only(left: 4, bottom: m.spacingMd),
        child: Text(text,
            style: TextStyle(
                fontSize: m.fontSizeLg,
                color: TvDesignTokens.textPrimary,
                fontWeight: FontWeight.bold)),
      );

  Widget _intro(TvMetrics m) => Container(
        padding: EdgeInsets.all(m.spacingLg),
        decoration: BoxDecoration(
          color: TvDesignTokens.surface,
          borderRadius: BorderRadius.circular(m.posterRadius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.extension, color: TvDesignTokens.brand, size: m.s(28)),
            SizedBox(width: m.spacingMd),
            Expanded(
              child: Text(
                'TV 端无法用文件导入插件，改从插件市场一键安装：遥控器选中即装，'
                '安装后在「已安装」里启用。',
                style: TextStyle(
                    fontSize: m.fontSizeSm,
                    height: 1.5,
                    color: TvDesignTokens.textSecondary),
              ),
            ),
          ],
        ),
      );

  Widget _hint(TvMetrics m, String text) => Padding(
        padding: EdgeInsets.symmetric(vertical: m.spacingMd, horizontal: 4),
        child: Text(text,
            style: TextStyle(
                fontSize: m.fontSizeSm, color: TvDesignTokens.textSecondary)),
      );

  Widget _miniAction(TvMetrics m, IconData icon, VoidCallback onSelect,
      {Color? color}) {
    return TvFocusable(
      padding: const EdgeInsets.all(4),
      onSelect: onSelect,
      child: Container(
        padding: EdgeInsets.all(m.spacingSm),
        decoration: BoxDecoration(
          color: TvDesignTokens.surfaceElevated,
          borderRadius: BorderRadius.circular(m.posterRadius),
        ),
        child: Icon(icon,
            color: color ?? TvDesignTokens.textPrimary, size: m.s(24)),
      ),
    );
  }

  Widget _card(
    TvMetrics m, {
    required String title,
    String? subtitle,
    required Widget trailing,
    required VoidCallback? onSelect,
    bool enabled = true,
  }) {
    final row = Container(
      padding: EdgeInsets.all(m.spacingMd),
      margin: EdgeInsets.only(bottom: m.spacingSm),
      decoration: BoxDecoration(
        color: TvDesignTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(m.posterRadius),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: m.fontSizeMd,
                        color: TvDesignTokens.textPrimary)),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  SizedBox(height: m.s(2)),
                  Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: m.fontSizeXs,
                          color: TvDesignTokens.textSecondary)),
                ],
              ],
            ),
          ),
          SizedBox(width: m.spacingMd),
          trailing,
        ],
      ),
    );
    if (onSelect == null) return row;
    return TvFocusable(
      padding: const EdgeInsets.all(4),
      onSelect: onSelect,
      child: row,
    );
  }
}
