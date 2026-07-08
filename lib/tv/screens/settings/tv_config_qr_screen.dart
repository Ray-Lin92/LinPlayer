import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/providers/server_providers.dart';
import '../../../core/services/config_transfer.dart';
import '../../theme/tv_design_tokens.dart';
import '../../theme/tv_metrics.dart';
import '../../widgets/tv_focusable.dart';

/// TV 端出配置二维码:把本机服务器打包成二维码,供手机「配置迁移 → 扫码导入」扫描。
/// 载荷离线内联在二维码里,不经网络。服务器过多放不下时提示改用 WebDAV/文件备份。
class TvConfigQrScreen extends ConsumerStatefulWidget {
  const TvConfigQrScreen({super.key});

  @override
  ConsumerState<TvConfigQrScreen> createState() => _TvConfigQrScreenState();
}

class _TvConfigQrScreenState extends ConsumerState<TvConfigQrScreen> {
  String? _payload;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _build());
  }

  Future<void> _build() async {
    try {
      final payload =
          await ConfigTransfer.encode(ref.read(serverListProvider));
      if (!mounted) return;
      setState(() {
        if (payload.length > ConfigTransfer.maxQrChars) {
          _error = '服务器较多,单个二维码放不下,请改用 WebDAV/文件备份迁移。';
        } else {
          _payload = payload;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.tv;
    return Scaffold(
      backgroundColor: TvDesignTokens.background,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(m.spacingXl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TvFocusable(
                    autofocus: true,
                    padding: EdgeInsets.all(m.spacingXs),
                    onSelect: () =>
                        context.canPop() ? context.pop() : context.go('/tv/home'),
                    child: Icon(Icons.arrow_back,
                        color: TvDesignTokens.textPrimary, size: m.s(32)),
                  ),
                  SizedBox(width: m.spacingMd),
                  Text(
                    '配置二维码',
                    style: TextStyle(
                      fontSize: m.fontSizeXxl,
                      color: TvDesignTokens.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              SizedBox(height: m.spacingXl),
              Expanded(child: _buildBody(m)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(TvMetrics m) {
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: TextStyle(
              fontSize: m.fontSizeMd, color: TvDesignTokens.textSecondary),
        ),
      );
    }
    if (_payload == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(m.spacingLg),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(m.posterRadius),
          ),
          child: QrImageView(
            data: _payload!,
            version: QrVersions.auto,
            size: m.s(280),
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
        ),
        SizedBox(width: m.spacingXxl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '用手机扫描左侧二维码',
                style: TextStyle(
                  fontSize: m.fontSizeXl,
                  color: TvDesignTokens.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: m.spacingMd),
              Text(
                '在手机 LinPlayer 打开「设置 → 配置迁移 → 扫码导入」,'
                '对准此码即可把本机服务器(含登录凭据)搬到手机。\n'
                '二维码含账号凭据,请勿外传。',
                style: TextStyle(
                  fontSize: m.fontSizeMd,
                  color: TvDesignTokens.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
