import 'dart:convert';

import 'plugin_context_bridge.dart';

/// data / addon 两种声明式 runtime 共用的小工具：模板插值、JSON 点路径取值、
/// 经宿主 ctx 桥（含 HTTPS + 白名单 + 防重定向）发起 HTTP。
///
/// 关键：HTTP 一律走 [PluginContextBridge.dispatch]('http', ...)，因此声明式插件与
/// JS 插件共享**完全相同**的权限门控和安全校验，不另开出网通道。

/// 点路径取值：`data.limit_bytes`、`items.0.id`。取不到返回 null。
dynamic jsonPath(dynamic obj, String path) {
  dynamic cur = obj;
  for (final seg in path.split('.')) {
    if (cur is Map) {
      cur = cur[seg];
    } else if (cur is List) {
      final i = int.tryParse(seg);
      cur = (i != null && i >= 0 && i < cur.length) ? cur[i] : null;
    } else {
      return null;
    }
    if (cur == null) return null;
  }
  return cur;
}

/// 模板插值：把 `{a.b.c}` 替换为 `vars` 里对应点路径的值（缺失→空串）。
String renderTemplate(String tpl, Map<String, dynamic> vars) {
  return tpl.replaceAllMapped(RegExp(r'\{([a-zA-Z0-9_.]+)\}'), (m) {
    final v = jsonPath(vars, m.group(1)!);
    return v == null ? '' : '$v';
  });
}

/// 递归对 JSON 结构里的字符串做模板插值（用于请求的 json 体 / headers / query）。
dynamic deepRender(dynamic node, Map<String, dynamic> vars) {
  if (node is String) return renderTemplate(node, vars);
  if (node is Map) {
    return node.map((k, v) => MapEntry('$k', deepRender(v, vars)));
  }
  if (node is List) return node.map((e) => deepRender(e, vars)).toList();
  return node;
}

/// 按声明式 `request` 发起 HTTP，返回 `{status, headers, body}` 或 null（失败）。
///
/// request: `{ method, url, headers?, query?, json? }`，各字段已就 [vars] 插值。
Future<Map<String, dynamic>?> declRequest(
    PluginContextBridge bridge, Map request, Map<String, dynamic> vars) async {
  final method = '${request['method'] ?? 'GET'}'.toLowerCase();
  final url = renderTemplate('${request['url'] ?? ''}', vars);
  if (url.isEmpty) return null;

  final opts = <String, dynamic>{};
  if (request['headers'] is Map) {
    opts['headers'] = deepRender(request['headers'], vars);
  }
  if (request['query'] is Map) {
    opts['query'] = deepRender(request['query'], vars);
  }

  final List<dynamic> args;
  if (method == 'post') {
    final body = request.containsKey('json') ? deepRender(request['json'], vars) : null;
    args = [url, body, opts];
  } else {
    args = [url, opts];
  }

  final raw = await bridge.dispatch('http', method, jsonEncode(args));
  final decoded = jsonDecode(raw);
  if (decoded is Map && decoded['ok'] == true && decoded['value'] is Map) {
    return Map<String, dynamic>.from(decoded['value'] as Map);
  }
  // {ok:false} 的错误（权限/白名单/网络）bridge 已记日志，这里安静失败。
  return null;
}

/// 便捷：拿当前 Emby 服务器 url（需 emby.read；无则空串）。data 的 `{serverUrl}`
/// 与 addon 的 `?serverUrl=` 都用它。
Future<String> currentServerUrl(PluginContextBridge bridge) async {
  try {
    final raw = await bridge.dispatch('emby', 'getServerInfo', '[]');
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['ok'] == true && decoded['value'] is Map) {
      final v = decoded['value'] as Map;
      return '${v['url'] ?? v['baseUrl'] ?? ''}';
    }
  } catch (_) {}
  return '';
}
