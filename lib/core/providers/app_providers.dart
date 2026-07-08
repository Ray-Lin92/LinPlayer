import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_interfaces.dart';
import '../api/emby_api.dart';
import '../api/mock_api.dart';
import '../services/cache_service.dart';
import '../services/ext_domain_service.dart';

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
final currentServerProvider = StateNotifierProvider<CurrentServerNotifier, ServerConfig?>((ref) {
  return CurrentServerNotifier();
});

class CurrentServerNotifier extends StateNotifier<ServerConfig?> {
  CurrentServerNotifier() : super(null);

  static const _currentServerKey = 'linplayer_current_server_id';

  Future<void> loadFromSaved(List<ServerConfig> servers) async {
    if (state != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverId = prefs.getString(_currentServerKey);
      if (serverId != null) {
        final saved = servers.where((s) => s.id == serverId).firstOrNull;
        if (saved != null) {
          super.state = saved;
        }
      }
    } catch (e) {
      // 加载失败
    }
  }

  Future<void> _saveCurrentServer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (state != null) {
        await prefs.setString(_currentServerKey, state!.id);
      } else {
        await prefs.remove(_currentServerKey);
      }
    } catch (e) {
      // 保存失败
    }
  }

  @override
  set state(ServerConfig? value) {
    super.state = value;
    _saveCurrentServer();
  }

  void clear() {
    state = null;
  }
}

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
  ServerListNotifier() : super([]) {
    _loadServers();
  }

  static const _serversKey = 'linplayer_servers';

  Future<void> _loadServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_serversKey);
      if (jsonStr != null) {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        state = jsonList.map((e) => _serverConfigFromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      // 加载失败时保持空列表
    }
  }

  Future<void> _saveServers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = state.map((s) => _serverConfigToJson(s)).toList();
      await prefs.setString(_serversKey, jsonEncode(jsonList));
    } catch (e) {
      // 保存失败时静默处理
    }
  }

  void addServer(ServerConfig server) {
    state = [...state, server];
    _saveServers();
  }

  void removeServer(String id) {
    state = state.where((s) => s.id != id).toList();
    _saveServers();
  }

  void updateServer(ServerConfig server) {
    state = state.map((s) => s.id == server.id ? server : s).toList();
    _saveServers();
  }

  void reorderServers(int oldIndex, int newIndex) {
    final servers = List<ServerConfig>.from(state);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final server = servers.removeAt(oldIndex);
    servers.insert(newIndex, server);
    state = servers;
    _saveServers();
  }

  void setActiveLine(String serverId, int lineIndex) {
    state = state.map((s) {
      if (s.id == serverId) {
        return s.copyWith(activeLineIndex: lineIndex);
      }
      return s;
    }).toList();
    _saveServers();
  }
}

Map<String, dynamic> _serverConfigToJson(ServerConfig s) {
  return {
    'id': s.id,
    'name': s.name,
    'baseUrl': s.baseUrl,
    'iconUrl': s.iconUrl,
    'remark': s.remark,
    'lines': s.lines.map((l) => {
      'id': l.id,
      'name': l.name,
      'url': l.url,
      'remark': l.remark,
    }).toList(),
    'activeLineIndex': s.activeLineIndex,
    'username': s.username,
    'authToken': s.authToken,
    'userId': s.userId,
  };
}

ServerConfig _serverConfigFromJson(Map<String, dynamic> json) {
  return ServerConfig(
    id: json['id'] as String,
    name: json['name'] as String,
    baseUrl: json['baseUrl'] as String,
    iconUrl: json['iconUrl'] as String?,
    remark: json['remark'] as String?,
    lines: (json['lines'] as List<dynamic>?)?.map((l) => ServerLine(
      id: l['id'] as String,
      name: l['name'] as String,
      url: l['url'] as String,
      remark: l['remark'] as String?,
    )).toList() ?? [],
    activeLineIndex: json['activeLineIndex'] as int? ?? 0,
    username: json['username'] as String?,
    authToken: json['authToken'] as String?,
    userId: json['userId'] as String?,
  );
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

/// 播放器内核Provider
final playerCoreProvider = StateProvider<String>((ref) => 'video_player');

/// 默认播放速度Provider
final defaultPlaybackSpeedProvider = StateProvider<double>((ref) => 1.0);

/// 快进步长Provider（秒）
final skipForwardStepProvider = StateProvider<int>((ref) => 10);

/// 长按快进倍速Provider
final longPressSpeedProvider = StateProvider<double>((ref) => 2.0);

/// 硬件解码Provider
final hardwareDecodingProvider = StateProvider<bool>((ref) => true);

/// 后台播放Provider
final backgroundPlaybackProvider = StateProvider<bool>((ref) => true);

/// 自动播放下一集Provider
final autoPlayNextProvider = StateProvider<bool>((ref) => true);

/// 弹幕开关Provider
final danmakuEnabledProvider = StateProvider<bool>((ref) => true);

/// 弹幕透明度Provider
final danmakuOpacityProvider = StateProvider<double>((ref) => 0.8);

/// 弹幕字号Provider
final danmakuFontSizeProvider = StateProvider<double>((ref) => 0.5);

/// 弹幕速度Provider
final danmakuSpeedProvider = StateProvider<double>((ref) => 0.5);

/// 弹幕密度Provider
final danmakuDensityProvider = StateProvider<double>((ref) => 0.5);

/// 弹幕延迟Provider (秒)
final danmakuDelayProvider = StateProvider<double>((ref) => 0.0);

/// 弹幕去重开关Provider
final danmakuDedupProvider = StateProvider<bool>((ref) => false);

/// 弹幕去重时间窗口Provider (秒)
final danmakuDedupWindowProvider = StateProvider<double>((ref) => 10.0);

/// 已加载的弹幕列表Provider
final loadedDanmakuProvider = StateProvider<List<DanmakuItem>>((ref) => []);

/// 弹幕屏蔽词列表Provider
final danmakuBlockwordsProvider = StateNotifierProvider<DanmakuBlockwordsNotifier, List<String>>((ref) {
  return DanmakuBlockwordsNotifier();
});

class DanmakuBlockwordsNotifier extends StateNotifier<List<String>> {
  DanmakuBlockwordsNotifier() : super([]);

  void addWord(String word) {
    if (word.isNotEmpty && !state.contains(word)) {
      state = [...state, word];
    }
  }

  void removeWord(String word) {
    state = state.where((w) => w != word).toList();
  }

  void importWords(List<String> words) {
    final newWords = words.where((w) => w.isNotEmpty && !state.contains(w)).toList();
    if (newWords.isNotEmpty) {
      state = [...state, ...newWords];
    }
  }

  void importUserBlocks(List<String> userIds) {
    final prefixedIds = userIds.map((id) => 'uid:$id').toList();
    importWords(prefixedIds);
  }

  void clear() {
    state = [];
  }
}

/// ==========================================
/// 播放器设置Providers
/// ==========================================

/// 首选字幕语言Provider
final preferredSubtitleLanguageProvider = StateProvider<String>((ref) => 'chi');

/// 首选音频语言Provider
final preferredAudioLanguageProvider = StateProvider<String>((ref) => 'jpn');

/// 首选版本Provider
final preferredVersionProvider = StateProvider<String>((ref) => '原盘');

/// 记忆亮度Provider
final rememberBrightnessProvider = StateProvider<bool>((ref) => true);

/// 当前播放亮度值Provider (0.0 - 1.0)
final playerBrightnessProvider = StateProvider<double>((ref) => 1.0);

/// 字幕字体Provider
final subtitleFontProvider = StateProvider<String>((ref) => '默认');

/// MPV自动修正杜比视界颜色Provider
final mpvDolbyVisionFixProvider = StateProvider<bool>((ref) => false);

/// 启用Impeller渲染引擎Provider
final impellerEnabledProvider = StateProvider<bool>((ref) => false);

/// EXO播放器使用libass渲染ASS字幕Provider
final exoLibassProvider = StateProvider<bool>((ref) => false);

/// 画面比例Provider
final aspectRatioProvider = StateProvider<String>((ref) => '自动');

/// 跳过片头开始时间（秒）
final skipOpeningStartProvider = StateProvider<int>((ref) => 0);

/// 跳过片头结束时间（秒）
final skipOpeningEndProvider = StateProvider<int>((ref) => 0);

/// 跳过片尾开始时间（秒）
final skipEndingStartProvider = StateProvider<int>((ref) => 0);

/// 跳过片尾结束时间（秒）
final skipEndingEndProvider = StateProvider<int>((ref) => 0);

/// 跳过模式：true=自动跳过, false=显示按钮
final skipAutoModeProvider = StateProvider<bool>((ref) => false);

/// 定时关闭剩余时间Provider
final sleepTimerRemainingProvider = StateProvider<Duration?>((ref) => null);

/// 字幕同步偏移Provider（秒）
final subtitleDelayProvider = StateProvider<double>((ref) => 0.0);

/// 音频同步偏移Provider（秒）
final audioDelayProvider = StateProvider<double>((ref) => 0.0);

/// 字幕大小Provider（0.0 - 1.0）
final subtitleSizeProvider = StateProvider<double>((ref) => 0.5);

/// 字幕位置Provider（0.0 - 1.0）
final subtitlePositionProvider = StateProvider<double>((ref) => 0.5);

/// 字幕黑色背景Provider
final subtitleBackgroundProvider = StateProvider<bool>((ref) => false);

/// ==========================================
/// 外观设置Providers
/// ==========================================

/// 隐藏每日推荐Provider
final hideDailyRecommendationsProvider = StateProvider<bool>((ref) => false);

/// 屏蔽的媒体库ID列表Provider
final hiddenLibrariesProvider = StateNotifierProvider<HiddenLibrariesNotifier, Set<String>>((ref) {
  return HiddenLibrariesNotifier();
});

class HiddenLibrariesNotifier extends StateNotifier<Set<String>> {
  HiddenLibrariesNotifier() : super({});

  void toggle(String libraryId) {
    if (state.contains(libraryId)) {
      state = Set.from(state)..remove(libraryId);
    } else {
      state = Set.from(state)..add(libraryId);
    }
  }

  void clear() {
    state = {};
  }
}

/// ==========================================
/// 缓存设置Providers
/// ==========================================

final imageCacheExpiryDaysProvider = StateProvider<int>((ref) => 14);

final videoCacheMaxSizeMBProvider = StateProvider<int>((ref) => 1024);

class CacheSizeInfo {
  final int imageBytes;
  final int videoBytes;
  CacheSizeInfo({required this.imageBytes, required this.videoBytes});
  int get totalBytes => imageBytes + videoBytes;
  String get imageFormatted => CacheService.formatBytes(imageBytes);
  String get videoFormatted => CacheService.formatBytes(videoBytes);
  String get totalFormatted => CacheService.formatBytes(totalBytes);
}

final cacheSizeProvider = FutureProvider<CacheSizeInfo>((ref) async {
  return CacheSizeInfo(
    imageBytes: await CacheService.getImageCacheSize(),
    videoBytes: await CacheService.getVideoCacheSize(),
  );
});

/// ==========================================
/// WebDAV备份Providers
/// ==========================================

/// WebDAV配置Provider
final webdavConfigProvider = StateNotifierProvider<WebdavConfigNotifier, WebdavConfig?>((ref) {
  return WebdavConfigNotifier();
});

class WebdavConfigNotifier extends StateNotifier<WebdavConfig?> {
  WebdavConfigNotifier() : super(null);

  void setConfig(String serverUrl, String username, String password) {
    state = WebdavConfig(
      serverUrl: serverUrl,
      username: username,
      password: password,
    );
  }

  void clearConfig() {
    state = null;
  }
}

class WebdavConfig {
  final String serverUrl;
  final String username;
  final String password;

  WebdavConfig({
    required this.serverUrl,
    required this.username,
    required this.password,
  });
}

/// ==========================================
/// 扩展线路同步Providers
/// ==========================================

/// 扩展线路同步服务Provider
final extDomainServiceProvider = Provider<ExtDomainService>((ref) {
  return ExtDomainService();
});

/// 扩展线路同步配置Provider（按服务器ID存储）
final extDomainConfigProvider = StateNotifierProvider<ExtDomainConfigNotifier, Map<String, ExtDomainConfig>>((ref) {
  return ExtDomainConfigNotifier();
});

class ExtDomainConfigNotifier extends StateNotifier<Map<String, ExtDomainConfig>> {
  ExtDomainConfigNotifier() : super({}) {
    _loadConfig();
  }

  static const _configKey = 'linplayer_ext_domain_configs';

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_configKey);
      if (jsonStr != null) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        state = json.map((key, value) => MapEntry(
          key,
          ExtDomainConfig(
            extDomainUrl: value['extDomainUrl'] as String,
            autoSync: value['autoSync'] as bool? ?? false,
          ),
        ));
      }
    } catch (e) {
      // 加载失败
    }
  }

  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = state.map((key, value) => MapEntry(key, {
        'extDomainUrl': value.extDomainUrl,
        'autoSync': value.autoSync,
      }));
      await prefs.setString(_configKey, jsonEncode(json));
    } catch (e) {
      // 保存失败
    }
  }

  void setConfig(String serverId, String extDomainUrl, {bool autoSync = false}) {
    state = {
      ...state,
      serverId: ExtDomainConfig(
        extDomainUrl: extDomainUrl,
        autoSync: autoSync,
      ),
    };
    _saveConfig();
  }

  void clearConfig(String serverId) {
    final newState = Map<String, ExtDomainConfig>.from(state);
    newState.remove(serverId);
    state = newState;
    _saveConfig();
  }

  void setAutoSync(String serverId, bool autoSync) {
    final config = state[serverId];
    if (config != null) {
      state = {
        ...state,
        serverId: ExtDomainConfig(
          extDomainUrl: config.extDomainUrl,
          autoSync: autoSync,
        ),
      };
      _saveConfig();
    }
  }

  ExtDomainConfig? getConfig(String serverId) => state[serverId];
}

class ExtDomainConfig {
  final String extDomainUrl;
  final bool autoSync;

  ExtDomainConfig({
    required this.extDomainUrl,
    this.autoSync = false,
  });
}

/// 同步线路结果Provider
final syncExtDomainsProvider = FutureProvider.family<List<ExtServerLine>, String>((ref, serverId) async {
  final service = ref.read(extDomainServiceProvider);
  final configs = ref.read(extDomainConfigProvider);
  final config = configs[serverId];
  final servers = ref.read(serverListProvider);

  if (config == null || config.extDomainUrl.isEmpty) {
    return [];
  }

  final server = servers.where((s) => s.id == serverId).firstOrNull;
  if (server == null || server.authToken == null) {
    return [];
  }

  try {
    return await service.fetchExtDomains(
      extDomainUrl: config.extDomainUrl,
      embyServerUrl: server.baseUrl,
      embyToken: server.authToken!,
    );
  } catch (e) {
    return [];
  }
});
