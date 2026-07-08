import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'danmaku_source.dart';
import '../api_interfaces.dart';

class DanmakuService {
  final List<DanmakuSource> _sources = [];
  DandanplaySource? _dandanplaySource;

  List<DanmakuSource> get sources => List.unmodifiable(_sources);
  DandanplaySource? get dandanplay => _dandanplaySource;

  void initDandanplay({required String appId, required String appSecret}) {
    _dandanplaySource = DandanplaySource(
      config: DanmakuSourceConfig(
        id: 'dandanplay',
        type: DanmakuSourceType.dandanplay,
        name: '弹弹Play',
        apiUrl: 'https://api.dandanplay.net',
        priority: 0,
      ),
      appId: appId,
      appSecret: appSecret,
    );
  }

  void addSource(DanmakuSourceConfig cfg) {
    _sources.removeWhere((s) => s.config.id == cfg.id);
    _sources.add(CustomDanmakuSource(config: cfg));
    _sources.sort((a, b) => a.config.priority.compareTo(b.config.priority));
  }

  void removeSource(String id) {
    _sources.removeWhere((s) => s.config.id == id);
  }

  List<DanmakuSource> get allSources {
    final list = <DanmakuSource>[];
    if (_dandanplaySource != null) list.add(_dandanplaySource!);
    list.addAll(_sources.where((s) => s.config.enabled));
    return list;
  }

  Future<DanmakuMatchResult> matchFromAll({
    required String fileName,
    String? fileHash,
    int? fileSize,
    double? videoDuration,
  }) async {
    for (final source in allSources) {
      try {
        final result = await source.match(
          fileName: fileName,
          fileHash: fileHash,
          fileSize: fileSize,
          videoDuration: videoDuration,
        );
        if (result.isMatched && result.matches.isNotEmpty) return result;
      } catch (_) {
        continue;
      }
    }
    return DanmakuMatchResult(isMatched: false, matches: []);
  }

  Future<List<DanmakuItem>> getCommentsFromAll(String episodeId, {String? preferredSourceId}) async {
    if (preferredSourceId != null) {
      final source = _findSource(preferredSourceId);
      if (source != null) {
        try {
          final items = await source.getComments(episodeId: episodeId);
          if (items.isNotEmpty) return items;
        } catch (_) {}
      }
    }
    for (final source in allSources) {
      if (source.config.id == preferredSourceId) continue;
      try {
        final items = await source.getComments(episodeId: episodeId);
        if (items.isNotEmpty) return items;
      } catch (_) {
        continue;
      }
    }
    return [];
  }

  Future<DanmakuSearchResult> searchFromAll(String keyword) async {
    final allAnimes = <DanmakuAnime>[];
    for (final source in allSources) {
      try {
        final result = await source.searchEpisodes(anime: keyword);
        allAnimes.addAll(result.animes);
      } catch (_) {
        continue;
      }
    }
    return DanmakuSearchResult(animes: allAnimes);
  }

  DanmakuSource? _findSource(String id) {
    if (_dandanplaySource?.config.id == id) return _dandanplaySource;
    try {
      return _sources.firstWhere((s) => s.config.id == id);
    } catch (_) {
      return null;
    }
  }
}

class DanmakuConfigRepository {
  static const _key = 'danmaku_custom_sources';

  Future<List<DanmakuSourceConfig>> loadSources() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr == null) return [];
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveSources(List<DanmakuSourceConfig> sources) async {
    final prefs = await SharedPreferences.getInstance();
    final list = sources.map((s) => _toJson(s)).toList();
    await prefs.setString(_key, jsonEncode(list));
  }

  DanmakuSourceConfig _fromJson(Map<String, dynamic> json) {
    return DanmakuSourceConfig(
      id: json['id'] as String,
      type: json['type'] == 'dandanplay'
          ? DanmakuSourceType.dandanplay
          : DanmakuSourceType.custom,
      name: json['name'] as String,
      apiUrl: json['apiUrl'] as String,
      priority: json['priority'] as int? ?? 0,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> _toJson(DanmakuSourceConfig config) {
    return {
      'id': config.id,
      'type': config.type.name,
      'name': config.name,
      'apiUrl': config.apiUrl,
      'priority': config.priority,
      'enabled': config.enabled,
    };
  }
}

final danmakuServiceProvider = StateNotifierProvider<DanmakuServiceNotifier, DanmakuService>((ref) {
  return DanmakuServiceNotifier();
});

class DanmakuServiceNotifier extends StateNotifier<DanmakuService> {
  final DanmakuConfigRepository _repo = DanmakuConfigRepository();

  DanmakuServiceNotifier() : super(DanmakuService()) {
    _init();
  }

  Future<void> _init() async {
    state.initDandanplay(
      appId: const String.fromEnvironment('DANDANPLAY_APP_ID', defaultValue: ''),
      appSecret: const String.fromEnvironment('DANDANPLAY_APP_SECRET', defaultValue: ''),
    );
    final sources = await _repo.loadSources();
    for (final cfg in sources) {
      state.addSource(cfg);
    }
    state = state;
  }

  Future<void> addCustomSource(DanmakuSourceConfig config) async {
    state.addSource(config);
    final sources = state.sources.map((s) => s.config).toList();
    await _repo.saveSources(sources);
    state = state;
  }

  Future<void> removeCustomSource(String id) async {
    state.removeSource(id);
    final sources = state.sources.map((s) => s.config).toList();
    await _repo.saveSources(sources);
    state = state;
  }
}
