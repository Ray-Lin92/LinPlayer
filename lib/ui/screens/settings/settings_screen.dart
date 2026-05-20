import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';

/// 设置主页
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsCard(
            icon: Icons.palette,
            title: '通用设置',
            subtitle: '外观、语言、启动页等',
            onTap: () => _showGeneralSettings(context),
          ),
          _SettingsCard(
            icon: Icons.play_circle,
            title: '播放器设置',
            subtitle: '内核、手势、播放行为等',
            onTap: () => _showPlayerSettings(context),
          ),
          _SettingsCard(
            icon: Icons.chat_bubble,
            title: '弹幕设置',
            subtitle: '外观、屏蔽词、延迟等',
            onTap: () => _showDanmakuSettings(context),
          ),
          _SettingsCard(
            icon: Icons.info,
            title: '关于',
            subtitle: '版本、开源许可、致谢',
            onTap: () => _showAbout(context),
          ),
          _SettingsCard(
            icon: Icons.backup,
            title: '备份与恢复',
            subtitle: '导出/导入服务器配置',
            onTap: () => _showBackupRestore(context),
          ),
        ],
      ),
    );
  }
  
  void _showGeneralSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const GeneralSettingsScreen()),
    );
  }
  
  void _showPlayerSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PlayerSettingsScreen()),
    );
  }
  
  void _showDanmakuSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DanmakuSettingsScreen()),
    );
  }
  
  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('LinPlayer v1.0.0'),
            SizedBox(height: 8),
            Text('GitHub: https://github.com/your-repo'),
            SizedBox(height: 8),
            Text('mpv version: 0.37.0'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          FilledButton(onPressed: () {}, child: const Text('检查更新')),
        ],
      ),
    );
  }
  
  void _showBackupRestore(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BackupRestoreScreen()),
    );
  }
}

/// 设置卡片
class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF5B8DEF).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF5B8DEF)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// 通用设置页
class GeneralSettingsScreen extends ConsumerWidget {
  const GeneralSettingsScreen({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    
    return Scaffold(
      appBar: AppBar(title: const Text('通用设置')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('外观'),
            subtitle: Text(themeMode.name),
            onTap: () => _showThemeSelector(context, ref),
          ),
          ListTile(
            title: const Text('语言'),
            subtitle: const Text('跟随系统'),
            onTap: () {},
          ),
          ListTile(
            title: const Text('启动页'),
            subtitle: const Text('首页'),
            onTap: () {},
          ),
          ListTile(
            title: const Text('缓存管理'),
            subtitle: const Text('1.2 GB'),
            trailing: TextButton(
              onPressed: () {},
              child: const Text('清除'),
            ),
          ),
          ListTile(
            title: const Text('聚合搜索优先级'),
            subtitle: const Text('服务器名称优先'),
            onTap: () {},
          ),
        ],
      ),
    );
  }
  
  void _showThemeSelector(BuildContext context, WidgetRef ref) {
    final current = ref.read(themeModeProvider);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('外观'),
        content: RadioGroup<ThemeModeOption>(
          groupValue: current,
          onChanged: (ThemeModeOption? value) {
            if (value != null) {
              ref.read(themeModeProvider.notifier).state = value;
            }
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ThemeModeOption.values.map((mode) => RadioListTile<ThemeModeOption>(
              title: Text(mode.name),
              value: mode,
            )).toList(),
          ),
        ),
      ),
    );
  }
}

/// 播放器设置页
class PlayerSettingsScreen extends StatelessWidget {
  const PlayerSettingsScreen({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('播放器设置')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('播放器内核'),
            subtitle: const Text('mpv（默认）'),
            onTap: () {},
          ),
          ListTile(
            title: const Text('默认播放速度'),
            subtitle: const Text('1.0x'),
            onTap: () {},
          ),
          ListTile(
            title: const Text('快进步长'),
            subtitle: const Text('10秒'),
            onTap: () {},
          ),
          ListTile(
            title: const Text('长按快进倍速'),
            subtitle: const Text('2x'),
            onTap: () {},
          ),
          SwitchListTile(
            title: const Text('硬件解码'),
            value: true,
            onChanged: (_) {},
          ),
          SwitchListTile(
            title: const Text('后台播放'),
            value: true,
            onChanged: (_) {},
          ),
          SwitchListTile(
            title: const Text('自动播放下一集'),
            value: true,
            onChanged: (_) {},
          ),
        ],
      ),
    );
  }
}

/// 弹幕设置页
class DanmakuSettingsScreen extends StatelessWidget {
  const DanmakuSettingsScreen({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('弹幕设置')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('弹幕开关'),
            value: true,
            onChanged: (_) {},
          ),
          ListTile(
            title: const Text('透明度'),
            subtitle: Slider(value: 0.8, onChanged: (_) {}),
          ),
          ListTile(
            title: const Text('字号'),
            subtitle: Slider(value: 0.5, onChanged: (_) {}),
          ),
          ListTile(
            title: const Text('速度'),
            subtitle: Slider(value: 0.5, onChanged: (_) {}),
          ),
          ListTile(
            title: const Text('密度'),
            subtitle: Slider(value: 0.5, onChanged: (_) {}),
          ),
          ListTile(
            title: const Text('屏蔽词管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

/// 备份与恢复页
class BackupRestoreScreen extends StatelessWidget {
  const BackupRestoreScreen({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.backup),
              label: const Text('导出备份'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.restore),
              label: const Text('导入备份'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.file_upload),
              label: const Text('导入服务器配置（JSON）'),
            ),
          ],
        ),
      ),
    );
  }
}
