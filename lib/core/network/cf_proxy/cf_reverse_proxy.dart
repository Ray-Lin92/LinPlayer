import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../services/app_logger.dart';

/// 本地反代：监听 `127.0.0.1:<随机端口>`，把明文 HTTP 桥接成到**优选 CF IP** 的 HTTPS。
///
/// 实现为**原始 TLS 隧道**（不是 HttpClient）：Dart 的 `HttpClient.connectionFactory`
/// 返回裸 Socket 时**不会自动做 TLS**（实测会把明文发到 443 → nginx 报
/// `400 The plain HTTP request was sent to HTTPS port`），而 `ConnectionTask` 是 final
/// 类、`SecureSocket.startConnect` 又无法把「连接 IP」与「SNI 域名」分开，所以无法用
/// HttpClient 做「钉 IP + 自定义 SNI」。这里改为：
///   读请求头 → 改写 Host、强制 Connection: close → 连到优选 IP 并
///   `SecureSocket.secure(host: 域名)`（SNI=域名）→ **原样双向转发字节**。
/// 因为不解析/不重组响应，Content-Length / Range(206) / chunked / 压缩 全部原样透传，
/// 接口、封面、视频流（含 seek）都正确。App 侧把该服务器 activeLineUrl 改写成
/// `http://127.0.0.1:port/...`，Dio 与 mpv 都自动走这条隧道，播放器无关、三端通用。
class CfReverseProxy {
  static final AppLogger _log = AppLogger();

  final String upstreamScheme; // https
  final String upstreamHost; // emby 域名
  final int upstreamPort; // 443
  final bool allowInsecureTls;

  String _ip; // 当前优选 IP
  ServerSocket? _server;

  CfReverseProxy({
    required this.upstreamScheme,
    required this.upstreamHost,
    required this.upstreamPort,
    required String ip,
    this.allowInsecureTls = false,
  }) : _ip = ip;

  int get port => _server?.port ?? 0;
  String get pinnedIp => _ip;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handleClient, onError: (e, _) {
      _log.w('CfProxy', '本地反代监听异常: $e');
    });
    _log.i('CfProxy',
        '反代已启动 127.0.0.1:$port -> $upstreamScheme://$upstreamHost:$upstreamPort via $_ip');
  }

  /// 切换优选 IP：之后**新建**的隧道连接走新 IP（无连接池，旧连接自然结束）。
  void updateIp(String ip) {
    if (ip == _ip) return;
    _ip = ip;
    _log.i('CfProxy', '反代上游切换到 $_ip（端口 $port 不变）');
  }

  Future<void> stop() async {
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
  }

  Future<void> _handleClient(Socket client) async {
    final headBuf = <int>[];
    var connected = false;
    SecureSocket? up;
    late final StreamSubscription<List<int>> clientSub;

    void closeBoth() {
      try {
        up?.destroy();
      } catch (_) {}
      try {
        client.destroy();
      } catch (_) {}
    }

    clientSub = client.listen(
      (data) async {
        if (connected) {
          // 请求头之后的字节（请求体）原样转发到上游。
          try {
            up?.add(data);
          } catch (_) {}
          return;
        }

        headBuf.addAll(data);
        final idx = _indexOfHeaderEnd(headBuf);
        if (idx < 0) {
          if (headBuf.length > 65536) closeBoth(); // 头过大，异常
          return;
        }

        final headBytes = headBuf.sublist(0, idx);
        final bodyLeftover = headBuf.sublist(idx + 4);
        final rewritten = _rewriteHead(headBytes);
        if (rewritten == null) {
          // 协议升级（WebSocket 等）不经反代：Emby 播放不依赖它。
          closeBoth();
          return;
        }

        connected = true;
        clientSub.pause();
        final SecureSocket secured;
        try {
          final addr = InternetAddress.tryParse(_ip);
          final raw = await Socket.connect(
              addr ?? _ip, upstreamPort,
              timeout: const Duration(seconds: 15));
          secured = await SecureSocket.secure(
            raw,
            host: upstreamHost, // SNI=真实域名
            supportedProtocols: const ['http/1.1'],
            onBadCertificate: (_) => allowInsecureTls,
          );
        } catch (e) {
          _log.w('CfProxy', '连上游失败 via $_ip: $e');
          closeBoth();
          return;
        }
        up = secured;

        // 上游 → 客户端：addStream 自带**背压**（客户端/播放器慢时暂停上游，避免大
        // 视频在内存里堆积），原样回灌响应字节（Content-Length/Range/chunked/压缩透传）。
        final pumping = client.addStream(secured);
        unawaited(pumping.then((_) {
          try {
            client.destroy();
          } catch (_) {}
        }).catchError((Object _) {
          closeBoth();
        }));

        // 写改写后的请求头 + 已读到的请求体首段，然后放行后续客户端字节。
        try {
          secured.add(rewritten);
          if (bodyLeftover.isNotEmpty) secured.add(bodyLeftover);
        } catch (_) {}
        clientSub.resume();
      },
      onError: (_) => closeBoth(),
      onDone: () {
        try {
          up?.destroy();
        } catch (_) {}
      },
      cancelOnError: true,
    );
  }

  /// 改写请求头：换 Host 为上游域名、去掉逐跳头、强制 Connection: close（一请求一隧道，
  /// 避免 keep-alive 复用时后续请求仍带旧 Host）。请求行（含已编码的路径/查询）原样保留。
  /// 检测到协议升级（Upgrade）返回 null。
  List<int>? _rewriteHead(List<int> headBytes) {
    final text = latin1.decode(headBytes, allowInvalid: true);
    final lines = text.split('\r\n');
    if (lines.isEmpty || lines.first.isEmpty) return null;

    final out = StringBuffer()
      ..write(lines.first) // 请求行：METHOD /path?query HTTP/1.1
      ..write('\r\n')
      ..write('Host: $upstreamHost\r\n');

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;
      final colon = line.indexOf(':');
      final name =
          (colon > 0 ? line.substring(0, colon) : line).trim().toLowerCase();
      if (name == 'host' ||
          name == 'connection' ||
          name == 'proxy-connection' ||
          name == 'keep-alive') {
        continue;
      }
      if (name == 'upgrade') return null;
      out
        ..write(line)
        ..write('\r\n');
    }
    out.write('Connection: close\r\n\r\n');
    return latin1.encode(out.toString());
  }

  int _indexOfHeaderEnd(List<int> data) {
    for (var i = 0; i + 3 < data.length; i++) {
      if (data[i] == 13 &&
          data[i + 1] == 10 &&
          data[i + 2] == 13 &&
          data[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }
}
