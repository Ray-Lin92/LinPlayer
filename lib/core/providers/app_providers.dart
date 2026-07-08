import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api_interfaces.dart';
import '../api/emby_api.dart';
import '../api/mock_api.dart';

/// 当前API客户端Provider
/// 
/// 基于当前活跃服务器自动创建EmbyApiClient；
/// 未登录时回退MockApiClient（用于首次启动/服务器列表页）。
final apiClientProvider = Provider<ApiClientFactory>((ref) {
  final server = ref.watch(currentServerProvider);
  if (server == null) return MockApiClient();
  final client = EmbyApiClient(
    baseUrl: server.activeLineUrl,
    authToken: server.authToken,
    userId: server.userId,
  );
  return client;
});

/// 认证状态Provider
final authStateProvider = StateProvider<AuthState>((ref) => AuthState.unauthenticated);

enum AuthState { unauthenticated, authenticating, authenticated, error }

/// 当前服务器Provider
final currentServerProvider = StateProvider<ServerConfig?>((ref) => null);

class ServerConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String? iconUrl;
  final String? remark;
  final List<ServerLine> lines;
  final int activeLineIndex;
  final String? username;
  final String? authToken;
  final String? userId;
  
  ServerConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.iconUrl,
    this.remark,
    this.lines = const [],
    this.activeLineIndex = 0,
    this.username,
    this.authToken,
    this.userId,
  });
  
  String get activeLineUrl => lines.isNotEmpty ? lines[activeLineIndex].url : baseUrl;
  
  ServerConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? iconUrl,
    String? remark,
    List<ServerLine>? lines,
    int? activeLineIndex,
    String? username,
    String? authToken,
    String? userId,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      iconUrl: iconUrl ?? this.iconUrl,
      remark: remark ?? this.remark,
      lines: lines ?? this.lines,
      activeLineIndex: activeLineIndex ?? this.activeLineIndex,
      username: username ?? this.username,
      authToken: authToken ?? this.authToken,
      userId: userId ?? this.userId,
    );
  }
}

class ServerLine {
  final String id;
  final String name;
  final String url;
  final String? remark;
  
  ServerLine({
    required this.id,
    required this.name,
    required this.url,
    this.remark,
  });
}

/// 服务器列表Provider
final serverListProvider = StateNotifierProvider<ServerListNotifier, List<ServerConfig>>((ref) {
  return ServerListNotifier();
});

class ServerListNotifier extends StateNotifier<List<ServerConfig>> {
  ServerListNotifier() : super([]);
  
  void addServer(ServerConfig server) {
    state = [...state, server];
  }
  
  void removeServer(String id) {
    state = state.where((s) => s.id != id).toList();
  }
  
  void updateServer(ServerConfig server) {
    state = state.map((s) => s.id == server.id ? server : s).toList();
  }
  
  void reorderServers(int oldIndex, int newIndex) {
    final servers = List<ServerConfig>.from(state);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final server = servers.removeAt(oldIndex);
    servers.insert(newIndex, server);
    state = servers;
  }
  
  void setActiveLine(String serverId, int lineIndex) {
    state = state.map((s) {
      if (s.id == serverId) {
        return s.copyWith(activeLineIndex: lineIndex);
      }
      return s;
    }).toList();
  }
}

/// 当前用户Provider
final currentUserProvider = FutureProvider<User?>((ref) async {
  final api = ref.watch(apiClientProvider);
  final authState = ref.watch(authStateProvider);
  
  if (authState != AuthState.authenticated) return null;
  
  try {
    return await api.user.getUser('current');
  } catch (e) {
    return null;
  }
});

/// 主题模式Provider
final themeModeProvider = StateProvider<ThemeModeOption>((ref) => ThemeModeOption.system);

enum ThemeModeOption { light, dark, system }
