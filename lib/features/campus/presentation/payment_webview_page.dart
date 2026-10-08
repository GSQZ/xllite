import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/state_panel.dart';

const schoolPaymentOrigin = 'https://newcard.xjit.edu.cn/';

/// Only payment app schemes are handed out of the WebView. Android intent
/// wrappers are reduced to the same allowlist instead of launching arbitrarily.
Uri? paymentExternalUri(Uri uri) {
  if (const {'weixin', 'alipay', 'alipays', 'alipayqr'}.contains(uri.scheme)) {
    return uri;
  }
  if (uri.scheme != 'intent') return null;
  final params = <String, String>{};
  for (final field in uri.fragment.split(';')) {
    final split = field.indexOf('=');
    if (split > 0) {
      params[field.substring(0, split)] = field.substring(split + 1);
    }
  }
  final scheme = params['scheme'];
  if (scheme == null ||
      !const {'weixin', 'alipay', 'alipays', 'alipayqr'}.contains(scheme)) {
    return null;
  }
  final body = uri
      .toString()
      .split('#Intent;')
      .first
      .substring('intent:'.length);
  return Uri.tryParse('$scheme:$body');
}

String paymentFormDocument(String html) {
  final submit = html.contains(RegExp(r'\.submit\s*\('))
      ? ''
      : "<script>window.addEventListener('load', function() { if (document.forms.length) document.forms[0].submit(); });</script>";
  return '<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body>$html$submit</body></html>';
}

class PaymentWebViewPage extends StatefulWidget {
  const PaymentWebViewPage({super.key, required this.result});
  final PaymentResult result;
  @override
  State<PaymentWebViewPage> createState() => _PaymentWebViewPageState();
}

class _PaymentWebViewPageState extends State<PaymentWebViewPage> {
  WebViewController? _controller;
  bool _loading = true;
  String? _error;
  final _refererLoaded = <String>{};
  bool _launching = false;
  @override
  void initState() {
    super.initState();
    final result = widget.result;
    if (result.preferredUrl == null && result.htmlPost.trim().isEmpty) {
      _loading = false;
      _error = result.type == PaymentResultType.wechatJsapi
          ? '学校返回的是微信内支付入口，本应用无法直接打开。请返回核对，并通过学校微信服务完成支付。'
          : '学校没有返回可打开的支付页面。请返回核对，不要重复下单。';
      return;
    }
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _navigate,
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (!mounted ||
                error.isForMainFrame == false ||
                const {-999, 102}.contains(error.errorCode)) {
              return;
            }
            setState(() {
              _loading = false;
              _error = '支付页面暂时无法加载，请返回核对订单后继续支付';
            });
          },
        ),
      );
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final result = widget.result;
      if (result.preferredUrl != null) {
        final uri = result.preferredUrl!;
        _refererLoaded.add(uri.toString());
        await _controller!.loadRequest(
          uri,
          headers: const {'Referer': schoolPaymentOrigin},
        );
      } else {
        final html = result.htmlPost;
        await _controller!.loadHtmlString(
          html.toLowerCase().contains('<html')
              ? html
              : paymentFormDocument(html),
          baseUrl: schoolPaymentOrigin,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '无法打开支付页面，请返回核对订单';
        });
      }
    }
  }

  Future<NavigationDecision> _navigate(NavigationRequest request) async {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    if (uri.scheme == 'https' && uri.userInfo.isEmpty) {
      if (request.isMainFrame &&
          uri.host == 'newcard.xjit.edu.cn' &&
          uri.fragment.split('?').first ==
              '/pages_plugins/recharge/webSuccess') {
        // Returning from checkout only refreshes account data; it is not a
        // verified payment receipt.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
        return NavigationDecision.prevent;
      }
      if ((uri.host == 'wx.tenpay.com' ||
              uri.host.endsWith('.wx.tenpay.com')) &&
          _refererLoaded.add(uri.toString())) {
        unawaited(
          _controller!.loadRequest(
            uri,
            headers: const {'Referer': schoolPaymentOrigin},
          ),
        );
        return NavigationDecision.prevent;
      }
      return NavigationDecision.navigate;
    }
    if (uri.toString() == 'about:blank') return NavigationDecision.navigate;
    final external = request.isMainFrame ? paymentExternalUri(uri) : null;
    if (external != null && !_launching) {
      _launching = true;
      var opened = false;
      try {
        opened = await launchUrl(
          external,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        /* Show a safe error below. */
      }
      _launching = false;
      if (mounted) {
        setState(() {
          _loading = false;
          _error = opened ? null : '未能打开支付应用，请确认已安装微信或支付宝';
        });
      }
    }
    return NavigationDecision.prevent;
  }

  void _back() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final error = _error;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回核对',
          icon: const Icon(Icons.close_rounded),
          onPressed: _back,
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('学校收银台'),
            Text(
              'newcard.xjit.edu.cn',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: AnimatedOpacity(
            opacity: _loading && error == null ? 1 : 0,
            duration: AppMotion.medium,
            child: LinearProgressIndicator(
              minHeight: 2,
              // Indeterminate only while visible.
              value: _loading && error == null ? null : 0,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_controller != null)
                  WebViewWidget(controller: _controller!),
                if (error != null)
                  ColoredBox(
                    color: scheme.surface,
                    child: StatePanel(
                      key: const Key('payment.error'),
                      icon: Icons.receipt_long_outlined,
                      title: '无法继续支付',
                      message: error,
                      actions: [
                        AppButton(
                          label: '返回核对',
                          icon: Icons.fact_check_outlined,
                          onPressed: _back,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Always visible: coming back is how the user checks the result.
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.xs,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '付款完成后返回核对，到账以余额和交易记录为准',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(
                      key: const Key('payment.back'),
                      onPressed: _back,
                      child: const Text('返回核对'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
