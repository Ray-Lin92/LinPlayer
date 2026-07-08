import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// 下载任务
class DownloadTask {
  String taskId;
  final String itemId;
  final String title;
  final String? episode;
  final String url;
  String status;
  int progress;
  String? localPath;
  
  DownloadTask({
    required this.taskId,
    required this.itemId,
    required this.title,
    this.episode,
    required this.url,
    this.status = 'pending',
    this.progress = 0,
    this.localPath,
  });
}

/// 下载服务
/// 
/// 使用 flutter_downloader 实现后台下载
class DownloadService extends ChangeNotifier {
  final Map<String, DownloadTask> _tasks = {};
  final ReceivePort _port = ReceivePort();
  bool _initialized = false;
  
  List<DownloadTask> get tasks => List.unmodifiable(_tasks.values);
  bool get isInitialized => _initialized;
  
  /// 初始化下载服务
  Future<void> initialize() async {
    if (_initialized) return;
    
    // 初始化 flutter_downloader
    await FlutterDownloader.initialize(
      debug: false,
      ignoreSsl: true,
    );
    
    // 注册回调
    IsolateNameServer.registerPortWithName(
      _port.sendPort,
      'downloader_send_port',
    );
    
    _port.listen((dynamic data) {
      final String taskId = data[0];
      final int status = data[1];
      final int progress = data[2];
      
      _updateTask(taskId, status, progress);
    });
    
    FlutterDownloader.registerCallback(downloadCallback);
    
    _initialized = true;
    notifyListeners();
  }
  
  /// 添加下载任务
  Future<String?> addDownload({
    required String itemId,
    required String title,
    String? episode,
    required String url,
  }) async {
    if (!_initialized) await initialize();
    
    try {
      // 获取下载目录
      final directory = await getApplicationDocumentsDirectory();
      final savePath = path.join(directory.path, 'downloads');
      
      // 创建目录
      final saveDir = Directory(savePath);
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
      
      // 生成文件名
      final fileName = '${title}_${DateTime.now().millisecondsSinceEpoch}.mp4';
      
      // 创建下载任务
      final taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: savePath,
        fileName: fileName,
        showNotification: true,
        openFileFromNotification: false,
        saveInPublicStorage: false,
      );
      
      if (taskId != null) {
        _tasks[taskId] = DownloadTask(
          taskId: taskId,
          itemId: itemId,
          title: title,
          episode: episode,
          url: url,
          localPath: path.join(savePath, fileName),
        );
        notifyListeners();
      }
      
      return taskId;
    } catch (e) {
      debugPrint('添加下载失败: $e');
      return null;
    }
  }
  
  /// 暂停下载
  Future<void> pauseDownload(String taskId) async {
    await FlutterDownloader.pause(taskId: taskId);
  }
  
  /// 恢复下载
  Future<void> resumeDownload(String taskId) async {
    final newTaskId = await FlutterDownloader.resume(taskId: taskId);
    if (newTaskId != null) {
      // 更新任务ID
      final task = _tasks[taskId];
      if (task != null) {
        _tasks.remove(taskId);
        task.taskId = newTaskId;
        _tasks[newTaskId] = task;
        notifyListeners();
      }
    }
  }
  
  /// 取消下载
  Future<void> cancelDownload(String taskId) async {
    await FlutterDownloader.cancel(taskId: taskId);
    _tasks.remove(taskId);
    notifyListeners();
  }
  
  /// 重试下载
  Future<String?> retryDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return null;
    
    // 取消旧任务
    await cancelDownload(taskId);
    
    // 创建新任务
    return addDownload(
      itemId: task.itemId,
      title: task.title,
      episode: task.episode,
      url: task.url,
    );
  }
  
  /// 删除下载任务和文件
  Future<void> removeDownload(String taskId) async {
    final task = _tasks[taskId];
    if (task != null && task.localPath != null) {
      // 删除文件
      try {
        final file = File(task.localPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('删除文件失败: $e');
      }
    }
    
    await FlutterDownloader.remove(
      taskId: taskId,
      shouldDeleteContent: true,
    );
    
    _tasks.remove(taskId);
    notifyListeners();
  }
  
  /// 获取所有下载任务
  Future<void> loadTasks() async {
    if (!_initialized) await initialize();
    
    final tasks = await FlutterDownloader.loadTasks();
    if (tasks != null) {
      for (final task in tasks) {
        _tasks[task.taskId] = DownloadTask(
          taskId: task.taskId,
          itemId: task.taskId, // 从文件名解析
          title: task.filename ?? '未知文件',
          url: task.url,
          status: task.status.toString(),
          progress: task.progress,
          localPath: path.join(task.savedDir, task.filename ?? ''),
        );
      }
      notifyListeners();
    }
  }
  
  /// 打开下载的文件
  Future<void> openDownloadedFile(String taskId) async {
    await FlutterDownloader.open(taskId: taskId);
  }
  
  /// 更新任务状态
  void _updateTask(String taskId, int status, int progress) {
    final task = _tasks[taskId];
    if (task != null) {
      task.progress = progress;
      
      // 转换状态
      switch (status) {
        case 1: // enqueued
          task.status = 'pending';
          break;
        case 2: // running
          task.status = 'downloading';
          break;
        case 3: // complete
          task.status = 'completed';
          break;
        case 4: // failed
          task.status = 'failed';
          break;
        case 5: // canceled
          task.status = 'canceled';
          break;
        case 6: // paused
          task.status = 'paused';
          break;
      }
      
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
    _port.close();
    super.dispose();
  }
  
  /// 下载回调（静态方法）
  @pragma('vm:entry-point')
  static void downloadCallback(String id, int status, int progress) {
    final SendPort? send = IsolateNameServer.lookupPortByName(
      'downloader_send_port',
    );
    send?.send([id, status, progress]);
  }
}
