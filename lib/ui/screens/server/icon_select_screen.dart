import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';

/// 图标选择页面
class IconSelectScreen extends ConsumerStatefulWidget {
  final String serverId;
  
  const IconSelectScreen({super.key, required this.serverId});
  
  @override
  ConsumerState<IconSelectScreen> createState() => _IconSelectScreenState();
}

class _IconSelectScreenState extends ConsumerState<IconSelectScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _urlController = TextEditingController();
  
  // Mock icon library data
  final List<IconLibrary> _libraries = [
    IconLibrary(
      name: 'Zzzの方形Emby图标',
      url: 'https://juhe.greentea520.xyz/share/78aspf.json',
      icons: [
        IconItem(name: 'SaturDay.Lite', url: 'https://cdn.picui.cn/vip/2026/01/04/695959d7a1e28.png'),
        IconItem(name: 'Shrek', url: 'https://cdn.picui.cn/vip/2026/01/04/69595a04ad8ca.png'),
      ],
    ),
  ];
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('图标选择'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '本地图片'),
            Tab(text: '网络图标库'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLocalTab(),
          _buildNetworkTab(),
        ],
      ),
    );
  }
  
  Widget _buildLocalTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '从相册选择',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              // TODO: 打开相册
            },
            icon: const Icon(Icons.photo_library),
            label: const Text('选择图片'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNetworkTab() {
    return Column(
      children: [
        // Library list
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('图标库', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ..._libraries.map((lib) => Card(
                child: ListTile(
                  title: Text(lib.name),
                  subtitle: Text(lib.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              )),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _showAddLibraryDialog(),
                icon: const Icon(Icons.add),
                label: const Text('添加网络图标库'),
              ),
            ],
          ),
        ),
        const Divider(),
        // Icon grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _libraries.expand((l) => l.icons).length,
            itemBuilder: (context, index) {
              final icon = _libraries.expand((l) => l.icons).elementAt(index);
              return _IconGridItem(
                icon: icon,
                onTap: () => _selectIcon(icon),
              );
            },
          ),
        ),
      ],
    );
  }
  
  void _showAddLibraryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加图标库'),
        content: TextField(
          controller: _urlController,
          decoration: const InputDecoration(
            labelText: 'JSON URL',
            hintText: 'https://example.com/icons.json',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              // TODO: 加载并解析图标库
              Navigator.pop(context);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
  
  void _selectIcon(IconItem icon) {
    final servers = ref.read(serverListProvider);
    final server = servers.firstWhere((s) => s.id == widget.serverId);
    ref.read(serverListProvider.notifier).updateServer(
      server.copyWith(iconUrl: icon.url),
    );
    Navigator.pop(context);
  }
}

class IconLibrary {
  final String name;
  final String url;
  final List<IconItem> icons;
  
  IconLibrary({required this.name, required this.url, required this.icons});
}

class IconItem {
  final String name;
  final String url;
  
  IconItem({required this.name, required this.url});
}

class _IconGridItem extends StatelessWidget {
  final IconItem icon;
  final VoidCallback onTap;
  
  const _IconGridItem({required this.icon, required this.onTap});
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  icon.url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            icon.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
