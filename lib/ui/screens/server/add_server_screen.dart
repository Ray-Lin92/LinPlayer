import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/api/emby_api.dart';
import '../../../core/providers/app_providers.dart';

/// 添加服务器页面
class AddServerScreen extends ConsumerStatefulWidget {
  const AddServerScreen({super.key});
  
  @override
  ConsumerState<AddServerScreen> createState() => _AddServerScreenState();
}

class _AddServerScreenState extends ConsumerState<AddServerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _urlController = TextEditingController();
  final _pathController = TextEditingController(text: '/emby');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _batchController = TextEditingController();
  
  bool _isLoading = false;
  String? _errorMessage;
  List<ServerLine> _parsedLines = [];
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    _pathController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _batchController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加服务器'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '手动输入'),
            Tab(text: '批量解析'),
            Tab(text: '导入配置'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildManualTab(),
          _buildBatchTab(),
          _buildImportTab(),
        ],
      ),
    );
  }
  
  Widget _buildManualTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://example.com',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pathController,
            decoration: const InputDecoration(
              labelText: '路径',
              hintText: '/emby',
              prefixIcon: Icon(Icons.folder),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: '用户名',
              prefixIcon: Icon(Icons.person),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: '密码',
              prefixIcon: Icon(Icons.lock),
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isLoading ? null : _addServer,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('连接并保存'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildBatchTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _batchController,
            decoration: const InputDecoration(
              labelText: '粘贴分享文本',
              hintText: 'XXX线路: https://example.com\n端口: XXXXX',
              border: OutlineInputBorder(),
            ),
            maxLines: 8,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _parseBatchText,
            child: const Text('解析'),
          ),
          if (_parsedLines.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('解析结果', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ..._parsedLines.map((line) => Card(
              child: ListTile(
                title: Text(line.name),
                subtitle: Text(line.url),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    setState(() {
                      _parsedLines.removeWhere((l) => l.id == line.id);
                    });
                  },
                ),
              ),
            )),
            const SizedBox(height: 16),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '用户名',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: '密码',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isLoading ? null : _addBatchServers,
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('添加所有线路'),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildImportTab() {
    final importController = TextEditingController();
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '从剪贴板导入',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '支持格式：单个服务器JSON或服务器列表JSON数组',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: importController,
            decoration: const InputDecoration(
              labelText: '粘贴JSON配置',
              hintText: '[{"name": "服务器", "url": "https://..."}]',
              border: OutlineInputBorder(),
            ),
            maxLines: 10,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _importFromJson(context, ref, importController.text),
            icon: const Icon(Icons.paste),
            label: const Text('解析并导入'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              try {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['json', 'txt'],
                  allowMultiple: false,
                );
                
                if (result != null && result.files.isNotEmpty) {
                  final file = result.files.first;
                  if (file.path != null) {
                    final content = await File(file.path!).readAsString();
                    if (context.mounted) {
                      _importFromJson(context, ref, content);
                    }
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('读取文件失败: $e')),
                  );
                }
              }
            },
            icon: const Icon(Icons.folder_open),
            label: const Text('从文件选择'),
          ),
        ],
      ),
    );
  }
  
  void _importFromJson(BuildContext context, WidgetRef ref, String jsonText) {
    if (jsonText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入JSON配置')),
      );
      return;
    }
    
    try {
      // 简单解析：尝试提取URL和名称
      final urlRegex = RegExp(r'["]url["]\s*:\s*["](https?://[^"]+)["]');
      final nameRegex = RegExp(r'["]name["]\s*:\s*["]([^"]+)["]');
      
      final urls = urlRegex.allMatches(jsonText).map((m) => m.group(1)!).toList();
      final names = nameRegex.allMatches(jsonText).map((m) => m.group(1)!).toList();
      
      if (urls.isEmpty) {
        throw Exception('未找到有效的服务器URL');
      }
      
      // 创建服务器配置
      for (var i = 0; i < urls.length; i++) {
        final url = urls[i];
        final name = i < names.length ? names[i] : '导入服务器 ${i + 1}';
        
        final server = ServerConfig(
          id: DateTime.now().millisecondsSinceEpoch.toString() + '_$i',
          name: name,
          baseUrl: url,
          lines: [ServerLine(
            id: 'default',
            name: '默认线路',
            url: url,
          )],
        );
        
        ref.read(serverListProvider.notifier).addServer(server);
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功导入 ${urls.length} 个服务器')),
      );
      
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: ${e.toString()}')),
      );
    }
  }
  
  void _parseBatchText() {
    final text = _batchController.text;
    if (text.isEmpty) return;
    
    final lines = <ServerLine>[];
    final lineRegex = RegExp(r'(.+?线路)\s*[:：]\s*(https?://[^\s]+)', caseSensitive: false);
    final portRegex = RegExp(r'端口\s*[:：]\s*(\d+)');
    
    var portSuffix = '';
    final portMatch = portRegex.firstMatch(text);
    if (portMatch != null) {
      portSuffix = ':${portMatch.group(1)}';
    }
    
    for (final match in lineRegex.allMatches(text)) {
      final name = match.group(1)?.trim() ?? '线路';
      var url = match.group(2)?.trim() ?? '';
      if (portSuffix.isNotEmpty && !url.contains(RegExp(r':\d+', dotAll: true))) {
        url = '$url$portSuffix';
      }
      lines.add(ServerLine(
        id: DateTime.now().millisecondsSinceEpoch.toString() + lines.length.toString(),
        name: name,
        url: url,
      ));
    }
    
    setState(() {
      _parsedLines = lines;
    });
  }
  
  Future<void> _addBatchServers() async {
    if (_parsedLines.isEmpty) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    
    try {
      final username = _usernameController.text.trim();
      final password = _passwordController.text;
      
      final firstLine = _parsedLines.first;
      final client = EmbyApiClient(baseUrl: firstLine.url);
      final authResult = await client.auth.login(username: username, password: password);
      final serverInfo = await client.server.getSystemInfo();
      
      final server = ServerConfig(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: serverInfo.serverName,
        baseUrl: firstLine.url,
        lines: _parsedLines,
        username: username,
        authToken: authResult.accessToken,
        userId: authResult.userId,
      );
      
      ref.read(serverListProvider.notifier).addServer(server);
      ref.read(currentServerProvider.notifier).state = server;
      ref.read(authStateProvider.notifier).state = AuthState.authenticated;
      
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() { _errorMessage = _formatError(e); });
    } finally {
      setState(() { _isLoading = false; });
    }
  }
  
  Future<void> _addServer() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final url = _urlController.text.trim();
      final path = _pathController.text.trim();
      final username = _usernameController.text.trim();
      final password = _passwordController.text;
      
      if (url.isEmpty) {
        throw Exception('服务器地址不能为空');
      }
      
      final fullUrl = path.isNotEmpty && path != '/' ? '$url$path' : url;
      
      final client = EmbyApiClient(baseUrl: fullUrl);
      
      final serverInfo = await client.server.getPublicInfo(fullUrl);
      
      if (username.isNotEmpty) {
        final authResult = await client.auth.login(username: username, password: password);
        
        final server = ServerConfig(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: serverInfo.serverName,
          baseUrl: fullUrl,
          lines: [ServerLine(
            id: 'default',
            name: '默认线路',
            url: fullUrl,
          )],
          username: username,
          authToken: authResult.accessToken,
          userId: authResult.userId,
        );
        
        ref.read(serverListProvider.notifier).addServer(server);
        ref.read(currentServerProvider.notifier).state = server;
        ref.read(authStateProvider.notifier).state = AuthState.authenticated;
        
        if (mounted) context.go('/home');
      } else {
        final server = ServerConfig(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: serverInfo.serverName,
          baseUrl: fullUrl,
          lines: [ServerLine(
            id: 'default',
            name: '默认线路',
            url: fullUrl,
          )],
        );
        
        ref.read(serverListProvider.notifier).addServer(server);
        
        if (mounted) context.pop();
      }
    } catch (e) {
      setState(() {
        _errorMessage = _formatError(e);
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  String _formatError(dynamic e) {
    if (e is Exception) {
      final msg = e.toString();
      if (msg.contains('401')) return '认证失败：用户名或密码错误';
      if (msg.contains('403')) return '访问被拒绝';
      if (msg.contains('502')) return '服务器网关错误';
      if (msg.contains('Connection') || msg.contains('timeout')) return '网络连接失败，请检查地址';
      return msg.replaceAll('Exception: ', '');
    }
    return e.toString();
  }
}
