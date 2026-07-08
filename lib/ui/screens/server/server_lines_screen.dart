import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';

/// 服务器线路管理页面
class ServerLinesScreen extends ConsumerWidget {
  final String serverId;
  
  const ServerLinesScreen({super.key, required this.serverId});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverListProvider);
    final server = servers.firstWhere((s) => s.id == serverId);
    
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text('服务器线路'),
            Text(
              server.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: server.lines.length,
              itemBuilder: (context, index) {
                final line = server.lines[index];
                final isActive = index == server.activeLineIndex;
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: isActive 
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  child: ListTile(
                    onTap: () {
                      ref.read(serverListProvider.notifier).setActiveLine(serverId, index);
                    },
                    title: Text(line.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(line.url),
                        if (line.remark != null)
                          Text('备注：${line.remark}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isActive)
                          Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () => _editLine(context, ref, serverId, line),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, size: 20, color: Theme.of(context).colorScheme.error),
                          onPressed: () => _deleteLine(context, ref, serverId, line),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: () => _addLine(context, ref, serverId),
              icon: const Icon(Icons.add),
              label: const Text('添加线路'),
            ),
          ),
        ],
      ),
    );
  }
  
  void _addLine(BuildContext context, WidgetRef ref, String serverId) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final remarkController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加线路'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: '线路名称'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: 'URL'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: remarkController,
              decoration: const InputDecoration(labelText: '备注'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final servers = ref.read(serverListProvider);
              final server = servers.firstWhere((s) => s.id == serverId);
              final newLine = ServerLine(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameController.text,
                url: urlController.text,
                remark: remarkController.text.isEmpty ? null : remarkController.text,
              );
              ref.read(serverListProvider.notifier).updateServer(
                server.copyWith(lines: [...server.lines, newLine]),
              );
              Navigator.pop(context);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
  
  void _editLine(BuildContext context, WidgetRef ref, String serverId, ServerLine line) {
    final nameController = TextEditingController(text: line.name);
    final urlController = TextEditingController(text: line.url);
    final remarkController = TextEditingController(text: line.remark ?? '');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑线路'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: '线路名称')),
            const SizedBox(height: 8),
            TextField(controller: urlController, decoration: const InputDecoration(labelText: 'URL')),
            const SizedBox(height: 8),
            TextField(controller: remarkController, decoration: const InputDecoration(labelText: '备注')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final servers = ref.read(serverListProvider);
              final server = servers.firstWhere((s) => s.id == serverId);
              final updatedLines = server.lines.map((l) {
                if (l.id == line.id) {
                  return ServerLine(
                    id: l.id,
                    name: nameController.text,
                    url: urlController.text,
                    remark: remarkController.text.isEmpty ? null : remarkController.text,
                  );
                }
                return l;
              }).toList();
              ref.read(serverListProvider.notifier).updateServer(
                server.copyWith(lines: updatedLines),
              );
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
  
  void _deleteLine(BuildContext context, WidgetRef ref, String serverId, ServerLine line) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除线路 "${line.name}" 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final servers = ref.read(serverListProvider);
              final server = servers.firstWhere((s) => s.id == serverId);
              ref.read(serverListProvider.notifier).updateServer(
                server.copyWith(lines: server.lines.where((l) => l.id != line.id).toList()),
              );
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
