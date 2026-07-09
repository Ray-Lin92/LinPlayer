import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 根级页面（首页 / 服务器列表）返回拦截：两秒内连按两次返回键才退出应用，
/// 避免在最外层误触一次系统返回就直接退到桌面。
///
/// 非根级页面无需包裹——它们通过 context.push 入栈，系统返回天然逐级 pop。
class DoubleBackToExit extends StatefulWidget {
  final Widget child;
  const DoubleBackToExit({super.key, required this.child});

  @override
  State<DoubleBackToExit> createState() => _DoubleBackToExitState();
}

class _DoubleBackToExitState extends State<DoubleBackToExit> {
  DateTime? _lastPress;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // canPop:false → 拦截 go_router 的“弹到父路由/退出”，改由下方计时逻辑决定。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastPress == null ||
            now.difference(_lastPress!) > const Duration(seconds: 2)) {
          _lastPress = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('再按一次返回键退出'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        SystemNavigator.pop();
      },
      child: widget.child,
    );
  }
}
