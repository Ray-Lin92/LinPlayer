import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum LogLevel { verbose, debug, info, warning, error }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
  });

  @override
  String toString() {
    final time = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}.${timestamp.millisecond.toString().padLeft(3, '0')}';
    final levelStr = level.name.toUpperCase().padRight(7);
    return '[$time] $levelStr [$tag] $message';
  }
}

/// 应用日志系统 - 全局单例
/// 
/// 使用方法:
/// ```dart
/// import 'app_logger.dart';
/// 
/// // 记录日志
/// log.i('Tag', '信息');
/// log.e('Tag', '错误', error, stackTrace);
/// 
/// // 导出日志
/// final path = await log.exportToFile();
/// ```
class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal() {
    i('AppLogger', '日志系统已初始化');
  }

  final List<LogEntry> _logs = [];
  static const int _maxLogs = 10000;

  void _log(LogLevel level, String tag, String message) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
    );
    _logs.add(entry);
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }
    if (kDebugMode) {
      debugPrint(entry.toString());
    }
  }

  void v(String tag, String message) => _log(LogLevel.verbose, tag, message);
  void d(String tag, String message) => _log(LogLevel.debug, tag, message);
  void i(String tag, String message) => _log(LogLevel.info, tag, message);
  void w(String tag, String message) => _log(LogLevel.warning, tag, message);
  void e(String tag, String message) => _log(LogLevel.error, tag, message);

  void eWithStack(String tag, String message, Object error, [StackTrace? stackTrace]) {
    final buffer = StringBuffer();
    buffer.writeln(message);
    buffer.writeln('  Error: $error');
    if (stackTrace != null) {
      buffer.writeln('  StackTrace:');
      final lines = stackTrace.toString().split('\n');
      for (var i = 0; i < lines.length && i < 20; i++) {
        buffer.writeln('    ${lines[i]}');
      }
    }
    _log(LogLevel.error, tag, buffer.toString());
  }

  List<LogEntry> getLogs({LogLevel? minLevel}) {
    if (minLevel == null) return List.unmodifiable(_logs);
    return List.unmodifiable(_logs.where((l) => l.level.index >= minLevel.index));
  }

  void clear() => _logs.clear();

  /// 导出日志为字符串，包含所有系统信息
  String exportAsString() {
    final buffer = StringBuffer();
    buffer.writeln('╔════════════════════════════════════════════════════════════╗');
    buffer.writeln('║                   LinPlayer 日志导出                       ║');
    buffer.writeln('╠════════════════════════════════════════════════════════════╣');
    buffer.writeln('║ 导出时间: ${DateTime.now().toIso8601String()}');
    buffer.writeln('║ 平台: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buffer.writeln('║ 本地名: ${Platform.localeName}');
    buffer.writeln('║ 日志条数: ${_logs.length} / $_maxLogs');
    buffer.writeln('╚════════════════════════════════════════════════════════════╝');
    buffer.writeln();
    
    if (_logs.isEmpty) {
      buffer.writeln('[警告] 当前没有日志记录。请在播放视频后重试导出。');
      buffer.writeln();
    }
    
    for (final entry in _logs) {
      buffer.writeln(entry.toString());
    }
    
    buffer.writeln();
    buffer.writeln('╔════════════════════════════════════════════════════════════╗');
    buffer.writeln('║                      日志结束                              ║');
    buffer.writeln('╚════════════════════════════════════════════════════════════╝');
    return buffer.toString();
  }

  /// 导出日志到文件，返回文件路径
  Future<String> exportToFile() async {
    final content = exportAsString();
    
    // 优先保存到 Download 目录
    try {
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (downloadsDir.existsSync()) {
        final fileName = 'linplayer_logs_${DateTime.now().millisecondsSinceEpoch}.txt';
        final file = File('${downloadsDir.path}/$fileName');
        await file.writeAsString(content);
        i('AppLogger', '日志已导出到: ${file.path}');
        return file.path;
      }
    } catch (e) {
      w('AppLogger', '保存到 Download 失败: $e');
    }

    // 回退到应用文档目录
    final appDir = await getApplicationDocumentsDirectory();
    final fileName = 'linplayer_logs_${DateTime.now().millisecondsSinceEpoch}.txt';
    final file = File('${appDir.path}/$fileName');
    await file.writeAsString(content);
    i('AppLogger', '日志已保存到应用目录: ${file.path}');
    return file.path;
  }
}

/// 全局日志便捷函数
final log = AppLogger();
