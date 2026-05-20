import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 下载任务状态
enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
}

/// 下载任务
class DownloadTask {
  final String id;
  final String itemId;
  final String title;
  final String? episode;
  final String url;
  final double progress;
  final DownloadStatus status;
  final String? errorMessage;
  final DateTime createdAt;
  
  DownloadTask({
    required this.id,
    required this.itemId,
    required this.title,
    this.episode,
    required this.url,
    this.progress = 0.0,
    this.status = DownloadStatus.pending,
    this.errorMessage,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  
  DownloadTask copyWith({
    String? id,
    String? itemId,
    String? title,
    String? episode,
    String? url,
    double? progress,
    DownloadStatus? status,
    String? errorMessage,
    DateTime? createdAt,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      title: title ?? this.title,
      episode: episode ?? this.episode,
      url: url ?? this.url,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// 下载任务列表Provider
final downloadTasksProvider = StateNotifierProvider<DownloadTasksNotifier, List<DownloadTask>>((ref) {
  return DownloadTasksNotifier();
});

class DownloadTasksNotifier extends StateNotifier<List<DownloadTask>> {
  DownloadTasksNotifier() : super([]);
  
  /// 添加下载任务
  void addTask(DownloadTask task) {
    state = [...state, task];
  }
  
  /// 更新任务进度
  void updateProgress(String taskId, double progress) {
    state = state.map((task) {
      if (task.id == taskId) {
        return task.copyWith(
          progress: progress,
          status: progress >= 1.0 ? DownloadStatus.completed : DownloadStatus.downloading,
        );
      }
      return task;
    }).toList();
  }
  
  /// 暂停任务
  void pauseTask(String taskId) {
    state = state.map((task) {
      if (task.id == taskId) {
        return task.copyWith(status: DownloadStatus.paused);
      }
      return task;
    }).toList();
  }
  
  /// 恢复任务
  void resumeTask(String taskId) {
    state = state.map((task) {
      if (task.id == taskId) {
        return task.copyWith(status: DownloadStatus.downloading);
      }
      return task;
    }).toList();
  }
  
  /// 标记失败
  void failTask(String taskId, String error) {
    state = state.map((task) {
      if (task.id == taskId) {
        return task.copyWith(status: DownloadStatus.failed, errorMessage: error);
      }
      return task;
    }).toList();
  }
  
  /// 删除任务
  void removeTask(String taskId) {
    state = state.where((task) => task.id != taskId).toList();
  }
  
  /// 清除已完成
  void clearCompleted() {
    state = state.where((task) => task.status != DownloadStatus.completed).toList();
  }
}
