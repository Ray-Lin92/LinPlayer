import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../../app_identity.dart';
import '../../services/app_logger.dart';
import '../proxy_http_client.dart';

/// 多线程加载（本地缓存预取代理）。
///
/// 起播时在 `127.0.0.1:<随机端口>` 起一个本地 HTTP 服务，把它当播放源交给播放器
/// （mpv / media_kit）。代理用 **2~4 个并发 Range 连接**对真实播放流**超前**拉取，
/// 在内存里维护一个有界的读前缓冲，再**顺序**喂给播放器；播放器自身的 `cache-on-disk`
/// 会把读到的数据落盘到 `video_cache/`，于是：
///   - 多连接聚合带宽 → 弱网下也能持续喂满，少卡顿；
///   - 播放器从本地（localhost / 自身磁盘缓存）读 → 抖动被缓冲吸收；
///   - 数据落盘，seek 回退命中播放器磁盘缓存，不重复拉。
///
/// 内存读前缓冲上限 [_maxReadAheadBytes]（128MB），且不超过用户设置的视频缓存上限；
/// 真正的整片落盘容量仍由播放器 `cache-on-disk` 按用户档位控制。
///
/// 失败即放弃：取不到文件大小 / 起服失败时返回 null，调用方回退直连在线地址。
/// 代理对上游的网络错误自带重试，播放器只面对始终在线的 localhost，弱网瞬断不冒泡。
class PrefetchProxy {
  PrefetchProxy._();
  static final PrefetchProxy instance = PrefetchProxy._();
  static final AppLogger _log = AppLogger();

  /// 每段大小：4MB。覆盖 ffmpeg 探流 + 单次 Range 请求体量适中。
  static const int _chunkSize = 4 * 1024 * 1024;

  /// 内存读前缓冲硬上限：128MB（足够吸收弱网抖动，又不撑爆 RAM）。
  static const int _maxReadAheadBytes = 128 * 1024 * 1024;

  HttpServer? _server;
  _Session? _session;

  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  /// 启动代理并返回本地播放 URL；失败返回 null（调用方回退在线直链）。
  ///
  /// [threads] 限定 2~4；[cacheLimitBytes] 为用户设置的视频缓存上限（用于给读前缓冲封顶）。
  Future<String?> start({
    required String upstreamUrl,
    required int threads,
    required int cacheLimitBytes,
  }) async {
    await stop();
    final t = threads.clamp(2, 4);
    final readAhead =
        math.min(_maxReadAheadBytes, math.max(_chunkSize * t * 2, cacheLimitBytes));
    try {
      final session = await _Session.create(
        upstreamUrl: upstreamUrl,
        threads: t,
        chunkSize: _chunkSize,
        readAheadBytes: readAhead,
        log: _log,
      );
      if (session == null) return null; // 取不到大小等 -> 放弃，直连
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(session.handle,
          onError: (Object e, _) => _log.w('Prefetch', '本地服务监听异常: $e'));
      _server = server;
      _session = session;
      final url = 'http://127.0.0.1:${server.port}/play';
      _log.i('Prefetch',
          '多线程预取代理启动 $url <- $upstreamUrl (${(session.totalSize / (1024 * 1024)).toStringAsFixed(0)}MB, $t 线程, 读前缓冲 ${(readAhead / (1024 * 1024)).toStringAsFixed(0)}MB)');
      return url;
    } catch (e) {
      _log.w('Prefetch', '启动失败，回退直连: $e');
      await stop();
      return null;
    }
  }

  Future<void> stop() async {
    _session?.dispose();
    _session = null;
    final s = _server;
    _server = null;
    if (s != null) {
      try {
        await s.close(force: true);
      } catch (_) {}
    }
  }
}

/// 一次播放会话：固定上游 URL，维护并发取数 + 有界读前缓冲 + 顺序供给。
class _Session {
  _Session._({
    required this.upstreamUrl,
    required this.threads,
    required this.chunkSize,
    required this.totalSize,
    required this.contentType,
    required this.readAheadChunks,
    required Dio dio,
    required AppLogger log,
  })  : _dio = dio,
        _log = log,
        _totalChunks = (totalSize + chunkSize - 1) ~/ chunkSize;

  final String upstreamUrl;
  final int threads;
  final int chunkSize;
  final int totalSize;
  final String contentType;
  final int readAheadChunks;
  final Dio _dio;
  final AppLogger _log;
  final int _totalChunks;

  // 已就绪的分段（绝对分段号 -> 字节）；顺序消费后即时清除，内存有界。
  final Map<int, List<int>> _ready = {};
  // 等待中的分段（worker 完成时 complete）。
  final Map<int, Completer<List<int>?>> _pending = {};

  int _serveChunk = 0; // 下一个要供给的分段
  int _fetchCursor = 0; // 下一个要分配给 worker 的分段
  int _generation = 0; // seek/切换时自增，作废在途结果
  bool _closed = false;
  Completer<void> _window = Completer<void>(); // 窗口/进度变化信号

  static Future<_Session?> create({
    required String upstreamUrl,
    required int threads,
    required int chunkSize,
    required int readAheadBytes,
    required AppLogger log,
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      responseType: ResponseType.bytes,
      validateStatus: (c) => c != null && c >= 200 && c < 400,
      headers: const {'User-Agent': kAppUserAgent, 'Accept': '*/*'},
    ));
    applyProxyToDio(dio);

    // 探总大小 + Content-Type：Range bytes=0-0 -> 206 Content-Range: bytes 0-0/<total>。
    int total = 0;
    String ctype = 'video/mp4';
    try {
      final resp = await dio
          .get<List<int>>(
            upstreamUrl,
            options: Options(headers: {'Range': 'bytes=0-0'}),
          )
          .timeout(const Duration(seconds: 8)); // 探测慢则快速放弃 -> 回退直连
      final cr = resp.headers.value('content-range');
      if (cr != null && cr.contains('/')) {
        total = int.tryParse(cr.split('/').last.trim()) ?? 0;
      }
      final ct = resp.headers.value('content-type');
      if (ct != null && ct.isNotEmpty) ctype = ct;
    } catch (e) {
      log.w('Prefetch', '探测文件大小失败: $e');
    }
    if (total <= chunkSize) {
      dio.close(force: true);
      return null; // 太小或未知，没必要代理
    }

    final readAheadChunks =
        math.max(threads * 2, readAheadBytes ~/ chunkSize);
    final s = _Session._(
      upstreamUrl: upstreamUrl,
      threads: threads,
      chunkSize: chunkSize,
      totalSize: total,
      contentType: ctype,
      readAheadChunks: readAheadChunks,
      dio: dio,
      log: log,
    );
    for (var i = 0; i < threads; i++) {
      unawaited(s._worker());
    }
    return s;
  }

  void dispose() {
    _closed = true;
    _generation++;
    _signalWindow();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
    _ready.clear();
    try {
      _dio.close(force: true);
    } catch (_) {}
  }

  void _signalWindow() {
    if (!_window.isCompleted) _window.complete();
    _window = Completer<void>();
  }

  // 把供给/取数游标重定位到字节 [byteStart]（新请求 = 播放器 seek 或首次连接）。
  void _reset(int byteStart) {
    _generation++;
    _serveChunk = byteStart ~/ chunkSize;
    _fetchCursor = _serveChunk;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
    _ready.clear();
    _signalWindow();
  }

  // 供给推进：腾出窗口、清除已消费分段。
  void _advanceServe(int next) {
    if (next <= _serveChunk) return;
    for (var c = _serveChunk; c < next; c++) {
      _ready.remove(c);
      _pending.remove(c);
    }
    _serveChunk = next;
    _signalWindow();
  }

  // worker：在窗口内顺序认领分段并拉取，写入就绪表。
  Future<void> _worker() async {
    while (!_closed) {
      final gen = _generation;
      // 认领：窗口未满且未到文件末尾才取下一段。
      if (_fetchCursor >= _totalChunks ||
          _fetchCursor > _serveChunk + readAheadChunks - 1) {
        await _window.future
            .timeout(const Duration(milliseconds: 250), onTimeout: () {});
        continue;
      }
      final c = _fetchCursor++; // 单 isolate：读后自增原子，分段唯一归属本 worker
      final comp = _pending.putIfAbsent(c, () => Completer<List<int>?>());
      List<int>? data;
      try {
        data = await _fetchChunk(c);
      } catch (e) {
        data = null;
        _log.w('Prefetch', '段 $c 拉取失败: $e');
      }
      if (_closed || gen != _generation) {
        if (!comp.isCompleted) comp.complete(null); // 作废，唤醒等待者
        continue;
      }
      if (data != null) _ready[c] = data;
      if (!comp.isCompleted) comp.complete(data);
    }
  }

  Future<List<int>> _fetchChunk(int c) async {
    final start = c * chunkSize;
    final end = math.min(start + chunkSize, totalSize) - 1;
    DioException? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final resp = await _dio.get<List<int>>(
          upstreamUrl,
          options: Options(headers: {'Range': 'bytes=$start-$end'}),
        );
        final body = resp.data;
        if (body != null && body.isNotEmpty) return body;
        throw DioException(
            requestOptions: resp.requestOptions, error: 'empty body');
      } on DioException catch (e) {
        last = e;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
        }
      }
    }
    throw last ?? StateError('fetch failed');
  }

  // 等待分段 c 就绪（由某个 worker 完成）。
  Future<List<int>?> _awaitChunk(int c) {
    final r = _ready[c];
    if (r != null) return Future.value(r);
    final comp = _pending.putIfAbsent(c, () => Completer<List<int>?>());
    return comp.future;
  }

  /// 处理播放器的一次 HTTP 请求（GET，可带 Range）。
  Future<void> handle(HttpRequest req) async {
    final resp = req.response;
    final range = _parseRange(req.headers.value(HttpHeaders.rangeHeader));
    final start = (range?.$1 ?? 0).clamp(0, totalSize - 1);
    final end = (range?.$2 ?? (totalSize - 1)).clamp(start, totalSize - 1);

    if (range != null && start >= totalSize) {
      resp.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      await _safeClose(resp);
      return;
    }

    resp.statusCode =
        range != null ? HttpStatus.partialContent : HttpStatus.ok;
    resp.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.contentTypeHeader, contentType)
      ..set(HttpHeaders.contentLengthHeader, '${end - start + 1}');
    if (range != null) {
      resp.headers.set('Content-Range', 'bytes $start-$end/$totalSize');
    }

    if (req.method == 'HEAD') {
      await _safeClose(resp);
      return;
    }

    // 重定位预取游标到本次请求起点（首次连接 / seek）。
    _reset(start);

    try {
      var pos = start;
      while (pos <= end && !_closed) {
        final c = pos ~/ chunkSize;
        final bytes = await _awaitChunk(c);
        if (bytes == null) break; // 作废 / 失败 -> 断流，播放器回退 fallback
        final within = pos - c * chunkSize;
        if (within >= bytes.length) break;
        final avail = bytes.length - within;
        final need = end - pos + 1;
        final n = avail < need ? avail : need;
        resp.add(bytes.sublist(within, within + n));
        await resp.flush(); // 端到端背压：播放器慢则在此阻塞，预取自然停在窗口内
        pos += n;
        if (within + n >= bytes.length) _advanceServe(c + 1);
      }
    } catch (_) {
      // 播放器断开（seek/退出）属正常，静默。
    } finally {
      await _safeClose(resp);
    }
  }

  Future<void> _safeClose(HttpResponse resp) async {
    try {
      await resp.close();
    } catch (_) {}
  }

  /// 解析 `bytes=start-end` / `bytes=start-` / `bytes=-suffix`。返回 (start, end?)。
  (int, int?)? _parseRange(String? header) {
    if (header == null || !header.startsWith('bytes=')) return null;
    final spec = header.substring(6).split(',').first.trim();
    final dash = spec.indexOf('-');
    if (dash < 0) return null;
    final startStr = spec.substring(0, dash).trim();
    final endStr = spec.substring(dash + 1).trim();
    if (startStr.isEmpty) {
      // 后缀范围 bytes=-N -> 末尾 N 字节
      final suffix = int.tryParse(endStr);
      if (suffix == null || suffix <= 0) return null;
      final s = math.max(0, totalSize - suffix);
      return (s, totalSize - 1);
    }
    final s = int.tryParse(startStr);
    if (s == null) return null;
    final e = endStr.isEmpty ? null : int.tryParse(endStr);
    return (s, e);
  }
}
