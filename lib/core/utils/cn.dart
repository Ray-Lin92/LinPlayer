
/// 简化的className工具，用于条件类名组合
/// 类似于 clsx + tailwind-merge 的简化版
class Cn {
  static String join(List<dynamic> classes) {
    final List<String> result = [];
    
    for (final item in classes) {
      if (item == null) continue;
      if (item is String && item.isNotEmpty) {
        result.add(item);
      } else if (item is List<String>) {
        result.addAll(item.where((s) => s.isNotEmpty));
      } else if (item is Map<String, bool>) {
        item.forEach((key, value) {
          if (value && key.isNotEmpty) result.add(key);
        });
      }
    }
    
    return result.join(' ');
  }
  
  static String cn(dynamic a, [dynamic b, dynamic c, dynamic d]) {
    return join([a, b, c, d]);
  }
}

/// 扩展String添加cn方法
extension CnExtension on String {
  String cn(dynamic other) {
    return Cn.cn(this, other);
  }
}
