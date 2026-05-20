import 'package:flutter/material.dart';

/// 本地下载页
class DownloadScreen extends StatelessWidget {
  const DownloadScreen({super.key});
  
  @override
  Widget build(BuildContext context) {
    // Mock download data
    final downloads = [
      {'title': '进击的巨人', 'episode': 'S1E5', 'progress': 1.0, 'status': 'completed'},
      {'title': '星际穿越', 'episode': '', 'progress': 0.75, 'status': 'downloading'},
      {'title': '千与千寻', 'episode': '', 'progress': 1.0, 'status': 'completed'},
    ];
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('本地下载'),
      ),
      body: downloads.isEmpty
          ? _buildEmptyState(context)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: downloads.length,
              itemBuilder: (context, index) {
                final download = downloads[index];
                final isCompleted = download['status'] == 'completed';
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Container(
                      width: 60,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.movie),
                    ),
                    title: Text(download['title'] as String),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (download['episode'] != '')
                          Text(download['episode'] as String),
                        if (!isCompleted) ...[
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: download['progress'] as double,
                            backgroundColor: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${((download['progress'] as double) * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                    trailing: isCompleted
                        ? IconButton(
                            icon: const Icon(Icons.play_arrow),
                            onPressed: () {},
                          )
                        : IconButton(
                            icon: const Icon(Icons.pause),
                            onPressed: () {},
                          ),
                  ),
                );
              },
            ),
    );
  }
  
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_done,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无下载内容',
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
