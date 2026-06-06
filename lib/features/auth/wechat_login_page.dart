import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/xjit_api_client.dart';
import '../../auth/auth_controller.dart';
import '../../core/config/app_config.dart';

class WechatLoginPage extends ConsumerStatefulWidget {
  const WechatLoginPage({super.key});

  @override
  ConsumerState<WechatLoginPage> createState() => _WechatLoginPageState();
}

class _WechatLoginPageState extends ConsumerState<WechatLoginPage> {
  WebViewController? _controller;
  Timer? _pollTimer;
  String? _state;
  String? _error;
  var _loading = true;
  var _completing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _pollTimer?.cancel();
    setState(() {
      _controller = null;
      _state = null;
      _error = null;
      _loading = true;
      _completing = false;
    });

    try {
      final data = await ref
          .read(xjitApiClientProvider)
          .wechatStart(apiBaseUrl: AppConfig.apiBaseUrl);
      final state = data['state']?.toString().trim();
      final authUrl = data['authUrl']?.toString().trim();
      if (state == null ||
          state.isEmpty ||
          authUrl == null ||
          authUrl.isEmpty) {
        throw const XjitApiException('扫码登录入口返回不完整');
      }

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: _handleNavigationRequest,
            onPageStarted: (_) => _setLoading(true),
            onPageFinished: (_) => _setLoading(false),
            onWebResourceError: (_) => _setLoading(false),
          ),
        );
      if (!mounted) {
        return;
      }
      setState(() {
        _controller = controller;
        _state = state;
      });
      await controller.loadRequest(Uri.parse(authUrl));
      _startPolling(state);
    } catch (error) {
      _showError(error.toString());
    } finally {
      _setLoading(false);
    }
  }

  Future<NavigationDecision> _handleNavigationRequest(
    NavigationRequest request,
  ) async {
    final uri = Uri.tryParse(request.url);
    if (uri == null) {
      return NavigationDecision.navigate;
    }

    final ticket = _ticketFromUri(uri);
    final state = _state;
    if (state != null && ticket != null) {
      unawaited(_complete(state: state, redirectUrl: request.url));
      return NavigationDecision.prevent;
    }

    if (_canOpenInWebView(uri)) {
      return NavigationDecision.navigate;
    }

    final opened = await _openExternalUri(uri);
    if (!opened) {
      _showSnack('无法打开外部授权链接');
    }
    return NavigationDecision.prevent;
  }

  void _startPolling(String state) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_checkStatus(state));
    });
  }

  Future<void> _checkStatus(String state) async {
    if (_completing) {
      return;
    }
    try {
      final data = await ref.read(xjitApiClientProvider).wechatStatus(state);
      await _finishIfReady(data);
    } catch (_) {
      // Polling is a fallback path; keep the WebView path available.
    }
  }

  Future<void> _complete({
    required String state,
    required String redirectUrl,
  }) async {
    if (_completing) {
      return;
    }
    setState(() {
      _completing = true;
      _error = null;
    });
    try {
      final data = await ref
          .read(xjitApiClientProvider)
          .wechatComplete(state: state, redirectUrl: redirectUrl);
      final finished = await _finishIfReady(data);
      if (!finished) {
        _showError('扫码结果还在确认中，请稍候');
      }
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() => _completing = false);
      }
    }
  }

  Future<bool> _finishIfReady(Map<String, dynamic> data) async {
    final status = data['status']?.toString().trim();
    final accessToken = data['accessToken']?.toString().trim();
    if (status == 'success' ||
        (accessToken != null && accessToken.isNotEmpty)) {
      _pollTimer?.cancel();
      await ref
          .read(authControllerProvider.notifier)
          .signInWithWechatData(data);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
      return true;
    }

    if (status == 'expired') {
      _pollTimer?.cancel();
      throw const XjitApiException('扫码登录已过期，请重新扫码');
    }
    if (status == 'error') {
      _pollTimer?.cancel();
      throw XjitApiException(
        data['error']?.toString().trim().isNotEmpty == true
            ? data['error'].toString()
            : '扫码登录失败',
      );
    }
    return false;
  }

  String? _ticketFromUri(Uri uri) {
    final ticket = uri.queryParameters['ticket'];
    if (ticket != null && ticket.isNotEmpty) {
      return ticket;
    }

    final fragmentUri = Uri.tryParse('https://local/?${uri.fragment}');
    final fragmentTicket = fragmentUri?.queryParameters['ticket'];
    if (fragmentTicket != null && fragmentTicket.isNotEmpty) {
      return fragmentTicket;
    }

    return uri.toString().contains('ticket=') ? '' : null;
  }

  bool _canOpenInWebView(Uri uri) {
    switch (uri.scheme.toLowerCase()) {
      case 'http':
      case 'https':
      case 'about':
      case 'data':
        return true;
    }
    return false;
  }

  Future<bool> _openExternalUri(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  void _setLoading(bool value) {
    if (mounted && _loading != value) {
      setState(() => _loading = value);
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _error = message;
      _loading = false;
    });
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('微信扫码登录'),
        actions: [
          IconButton(
            onPressed: _start,
            icon: const Icon(Icons.refresh),
            tooltip: '重新获取二维码',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (controller == null)
            Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : _WechatLoginError(message: _error!, onRetry: _start),
            )
          else
            WebViewWidget(controller: controller),
          if (_loading || _completing)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (controller != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.94),
                  border: Border(
                    top: BorderSide(
                      color: colors.outlineVariant.withValues(alpha: 0.65),
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.qr_code_scanner_outlined,
                          size: 18,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error ??
                                '受微信限制，同一台手机截图识别二维码无法解决。请用另一台设备扫码，或返回使用账号密码登录。',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WechatLoginError extends StatelessWidget {
  const _WechatLoginError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 34),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重新获取二维码'),
          ),
        ],
      ),
    );
  }
}
