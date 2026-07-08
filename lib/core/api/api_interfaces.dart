/// ============================================================
/// API 抽象接口层 - 供后端开发人员接入
/// 
/// 使用说明：
/// 1. 实现这些接口的具体类（如 EmbyApiClient）
/// 2. 在 providers 中替换为实际实现
/// 3. UI层只依赖这些抽象接口，不依赖具体实现
/// ============================================================

// ==================== 认证相关 ====================

abstract class AuthApi {
  /// 用户登录
  /// POST /Users/AuthenticateByName
  Future<AuthResult> login({required String username, required String password});
  
  /// 登出
  /// POST /Sessions/Logout
  Future<void> logout();
  
  /// 获取当前用户信息
  /// GET /Users/Me
  Future<User> getCurrentUser();
  
  /// 刷新Token（如支持）
  Future<AuthResult> refreshToken();
}

class AuthResult {
  final String accessToken;
  final String userId;
  final String serverId;
  final User user;
  
  AuthResult({
    required this.accessToken,
    required this.userId,
    required this.serverId,
    required this.user,
  });
}

// ==================== 用户相关 ====================

abstract class UserApi {
  /// 获取用户资料
  Future<User> getUser(String userId);
}

class User {
  final String id;
  final String name;
  final String? primaryImageTag;
  final bool? hasPassword;
  final List<String>? configuration;
  
  User({
    required this.id,
    required this.name,
    this.primaryImageTag,
    this.hasPassword,
    this.configuration,
  });
}

// ==================== 服务器相关 ====================

abstract class ServerApi {
  /// 获取公开服务器信息（无需认证）
  /// GET /System/Info/Public
  Future<ServerInfo> getPublicInfo(String baseUrl);
  
  /// 获取系统信息
  /// GET /System/Info
  Future<ServerInfo> getSystemInfo();
  
  /// 测试连接
  Future<bool> testConnection(String baseUrl);
}

class ServerInfo {
  final String id;
  final String serverName;
  final String version;
  final String? productName;
  final String? operatingSystem;
  
  ServerInfo({
    required this.id,
    required this.serverName,
    required this.version,
    this.productName,
    this.operatingSystem,
  });
}

// ==================== 首页相关 ====================

abstract class HomeApi {
  /// 获取继续观看列表
  /// GET /Users/{UserId}/Items/Resume
  Future<List<MediaItem>> getResumeItems();
  
  /// 获取下一集
  /// GET /Shows/NextUp
  Future<List<MediaItem>> getNextUp();
  
  /// 获取媒体库列表
  /// GET /Users/{userId}/Views
  Future<List<Library>> getLibraries();
  
  /// 获取最新添加
  /// GET /Users/{UserId}/Items/Latest
  Future<List<MediaItem>> getLatestItems(String libraryId, {int limit = 20});
  
  /// 获取随机推荐
  Future<List<MediaItem>> getRandomRecommendations({int limit = 8});
}

// ==================== 媒体库相关 ====================

abstract class LibraryApi {
  /// 获取媒体库内容
  /// GET /Users/{UserId}/Items
  Future<List<MediaItem>> getLibraryItems({
    required String libraryId,
    String? sortBy,
    String? sortOrder,
    int startIndex = 0,
    int limit = 50,
  });
  
  /// 获取筛选条件
  /// GET /Items/Filters
  Future<Filters> getFilters(String libraryId);
}

class Filters {
  final List<String> genres;
  final List<String> years;
  final List<String> officialRatings;
  
  Filters({
    required this.genres,
    required this.years,
    required this.officialRatings,
  });
}

// ==================== 媒体项相关 ====================

abstract class MediaApi {
  /// 获取单项详情
  /// GET /Items/{Id}
  Future<MediaItem> getItemDetails(String itemId);
  
  /// 获取相似推荐
  /// GET /Items/{Id}/Similar
  Future<List<MediaItem>> getSimilarItems(String itemId);
  
  /// 获取季列表
  /// GET /Shows/{Id}/Seasons
  Future<List<Season>> getSeasons(String seriesId);
  
  /// 获取集列表
  /// GET /Shows/{Id}/Episodes
  Future<List<Episode>> getEpisodes(String seriesId, {String? seasonId});
  
  /// 获取人物参演
  /// GET /Persons/{Name}/Items
  Future<List<Person>> getPersonItems(String personName);
}

class MediaItem {
  final String id;
  final String name;
  final String type; // 'Movie', 'Series', 'Episode', 'Season'
  final String? overview;
  final String? primaryImageTag;
  final String? backdropImageTag;
  final double? communityRating;
  final String? officialRating;
  final DateTime? premiereDate;
  final int? runTimeTicks;
  final int? productionYear;
  final List<String>? genres;
  final List<String>? tags;
  final UserData? userData;
  final String? seriesName;
  final int? indexNumber;
  final int? parentIndexNumber;
  final String? seriesId;
  final String? seasonId;
  final String? mediaType; // 'Video', 'Audio'
  
  MediaItem({
    required this.id,
    required this.name,
    required this.type,
    this.overview,
    this.primaryImageTag,
    this.backdropImageTag,
    this.communityRating,
    this.officialRating,
    this.premiereDate,
    this.runTimeTicks,
    this.productionYear,
    this.genres,
    this.tags,
    this.userData,
    this.seriesName,
    this.indexNumber,
    this.parentIndexNumber,
    this.seriesId,
    this.seasonId,
    this.mediaType,
  });
  
  String? get formattedRuntime {
    if (runTimeTicks == null) return null;
    final minutes = (runTimeTicks! / 10000000 / 60).round();
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }
  
  bool get isWatched => userData?.played ?? false;
  double? get progress => userData?.playbackPositionTicks != null && runTimeTicks != null
      ? userData!.playbackPositionTicks! / runTimeTicks!
      : null;
}

class UserData {
  final double? playbackPositionTicks;
  final bool? played;
  final bool? isFavorite;
  final double? playCount;
  
  UserData({
    this.playbackPositionTicks,
    this.played,
    this.isFavorite,
    this.playCount,
  });
}

class Season {
  final String id;
  final String name;
  final int? indexNumber;
  final String? primaryImageTag;
  final String seriesId;
  
  Season({
    required this.id,
    required this.name,
    this.indexNumber,
    this.primaryImageTag,
    required this.seriesId,
  });
}

class Episode {
  final String id;
  final String name;
  final int? indexNumber;
  final String? primaryImageTag;
  final String seriesId;
  final String seasonId;
  final int? runTimeTicks;
  final UserData? userData;
  final String? overview;
  
  Episode({
    required this.id,
    required this.name,
    this.indexNumber,
    this.primaryImageTag,
    required this.seriesId,
    required this.seasonId,
    this.runTimeTicks,
    this.userData,
    this.overview,
  });
  
  String? get formattedRuntime {
    if (runTimeTicks == null) return null;
    final minutes = (runTimeTicks! / 10000000 / 60).round();
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }
}

class Person {
  final String id;
  final String name;
  final String? primaryImageTag;
  final String? role;
  final String? type; // 'Actor', 'Director', etc.
  
  Person({
    required this.id,
    required this.name,
    this.primaryImageTag,
    this.role,
    this.type,
  });
}

class Library {
  final String id;
  final String name;
  final String? primaryImageTag;
  final String collectionType; // 'movies', 'tvshows', etc.
  
  Library({
    required this.id,
    required this.name,
    this.primaryImageTag,
    required this.collectionType,
  });
}

// ==================== 搜索相关 ====================

abstract class SearchApi {
  /// 搜索建议
  /// GET /Search/Hints
  Future<List<MediaItem>> getSearchHints(String query);
  
  /// 搜索
  /// GET /Users/{UserId}/Items?SearchTerm=...
  Future<List<MediaItem>> search(String query, {bool recursive = true});
  
  /// 聚合搜索（跨服务器）
  Future<Map<String, List<MediaItem>>> searchAggregate(String query);
}

// ==================== 播放相关 ====================

abstract class PlaybackApi {
  /// 获取播放信息
  /// POST /Items/{Id}/PlaybackInfo
  Future<PlaybackInfo> getPlaybackInfo(String itemId);
  
  /// 获取视频流
  /// GET /Videos/{Id}/stream
  String getVideoStreamUrl(String itemId);
  
  /// 获取字幕流URL
  /// GET /Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/Stream.{codec}
  String getSubtitleStreamUrl(String itemId, String mediaSourceId, int index, String codec);
  
  /// 播放开始上报
  /// POST /Sessions/Playing
  Future<void> reportPlaybackStart(PlaybackStartInfo info);
  
  /// 播放进度上报
  /// POST /Sessions/Playing/Progress
  Future<void> reportPlaybackProgress(PlaybackProgressInfo info);
  
  /// 播放停止上报
  /// POST /Sessions/Playing/Stopped
  Future<void> reportPlaybackStopped(PlaybackStopInfo info);
}

class PlaybackInfo {
  final String itemId;
  final List<MediaSource> mediaSources;
  final List<PlaybackDeviceProfile>? deviceProfiles;
  
  PlaybackInfo({
    required this.itemId,
    required this.mediaSources,
    this.deviceProfiles,
  });
}

class MediaSource {
  final String id;
  final String? name;
  final String? path;
  final String? container;
  final int? size;
  final int? runTimeTicks;
  final List<MediaStream> mediaStreams;
  
  MediaSource({
    required this.id,
    this.name,
    this.path,
    this.container,
    this.size,
    this.runTimeTicks,
    required this.mediaStreams,
  });
}

class MediaStream {
  final int index;
  final String type; // 'Video', 'Audio', 'Subtitle'
  final String? codec;
  final String? language;
  final String? title;
  final bool? isDefault;
  final bool? isExternal;
  final String? displayTitle;
  final String? videoCodec;
  final int? width;
  final int? height;
  final int? channels;
  
  MediaStream({
    required this.index,
    required this.type,
    this.codec,
    this.language,
    this.title,
    this.isDefault,
    this.isExternal,
    this.displayTitle,
    this.videoCodec,
    this.width,
    this.height,
    this.channels,
  });
  
  bool get isVideo => type == 'Video';
  bool get isAudio => type == 'Audio';
  bool get isSubtitle => type == 'Subtitle';
  String get resolution {
    final w = width;
    final h = height;
    if (w == null || h == null) return '';
    if (h >= 2160) return '4K';
    if (h >= 1080) return '1080p';
    if (h >= 720) return '720p';
    return '${h}p';
  }
}

class PlaybackDeviceProfile {
  // 设备能力配置
  final String name;
  final int? maxStreamingBitrate;
  
  PlaybackDeviceProfile({
    required this.name,
    this.maxStreamingBitrate,
  });
}

class PlaybackStartInfo {
  final String itemId;
  final String mediaSourceId;
  final String? audioStreamIndex;
  final String? subtitleStreamIndex;
  final String? playMethod;
  
  PlaybackStartInfo({
    required this.itemId,
    required this.mediaSourceId,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.playMethod,
  });
}

class PlaybackProgressInfo {
  final String itemId;
  final String mediaSourceId;
  final int positionTicks;
  final bool isPaused;
  final bool isMuted;
  final double volumeLevel;
  
  PlaybackProgressInfo({
    required this.itemId,
    required this.mediaSourceId,
    required this.positionTicks,
    this.isPaused = false,
    this.isMuted = false,
    this.volumeLevel = 1.0,
  });
}

class PlaybackStopInfo {
  final String itemId;
  final String mediaSourceId;
  final int positionTicks;
  
  PlaybackStopInfo({
    required this.itemId,
    required this.mediaSourceId,
    required this.positionTicks,
  });
}

// ==================== 收藏相关 ====================

abstract class FavoriteApi {
  /// 添加到收藏
  /// POST /Users/{UserId}/FavoriteItems/{Id}
  Future<void> addFavorite(String itemId);
  
  /// 取消收藏
  /// DELETE /Users/{UserId}/FavoriteItems/{Id}
  Future<void> removeFavorite(String itemId);
}

// ==================== 会话相关 ====================

abstract class SessionApi {
  /// 获取会话列表
  /// GET /Sessions
  Future<List<Session>> getSessions();
}

class Session {
  final String id;
  final String? userName;
  final String? client;
  final String? deviceName;
  final bool? isNowPlaying;
  final NowPlayingItem? nowPlayingItem;
  
  Session({
    required this.id,
    this.userName,
    this.client,
    this.deviceName,
    this.isNowPlaying,
    this.nowPlayingItem,
  });
}

class NowPlayingItem {
  final String id;
  final String name;
  final String? seriesName;
  final int? runTimeTicks;
  final int? playbackPositionTicks;
  
  NowPlayingItem({
    required this.id,
    required this.name,
    this.seriesName,
    this.runTimeTicks,
    this.playbackPositionTicks,
  });
}

// ==================== 图片相关 ====================

abstract class ImageApi {
  /// 获取图片URL
  String getImageUrl({
    required String itemId,
    String? imageTag,
    String imageType = 'Primary',
    int? maxWidth,
    int? maxHeight,
    double quality = 90,
  });
  
  /// 获取主封面
  String getPrimaryImageUrl(String itemId, {String? tag, int? maxWidth});
  
  /// 获取背景图
  String getBackdropImageUrl(String itemId, {String? tag, int? maxWidth});
}

// ==================== 弹幕相关 ====================

abstract class DanmakuApi {
  /// 搜索弹幕
  Future<List<DanmakuItem>> searchDanmaku({
    required String title,
    int? episode,
    String? source, // 'dandanplay', 'danmu_api', 'misaka'
  });
  
  /// 获取弹幕列表
  Future<List<DanmakuItem>> getDanmakuComments(String episodeId);
}

class DanmakuItem {
  final double time; // 出现时间(秒)
  final String text;
  final int type; // 0=滚动, 1=顶部, 2=底部
  final int color;
  final double size;
  
  DanmakuItem({
    required this.time,
    required this.text,
    this.type = 0,
    this.color = 0xFFFFFFFF,
    this.size = 25,
  });
}

// ==================== API工厂 ====================

/// API工厂接口 - 每个服务器实例一个
abstract class ApiClientFactory {
  AuthApi get auth;
  UserApi get user;
  ServerApi get server;
  HomeApi get home;
  LibraryApi get library;
  MediaApi get media;
  SearchApi get search;
  PlaybackApi get playback;
  FavoriteApi get favorite;
  SessionApi get session;
  ImageApi get image;
  DanmakuApi get danmaku;
  
  /// 切换活跃线路
  void switchLine(String lineUrl);
  
  /// 获取当前线路
  String get currentLine;
  
  /// 设置认证Token
  void setAuthToken(String token);
  
  /// 清除认证
  void clearAuth();
}
