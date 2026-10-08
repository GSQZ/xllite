import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'feature_data_page.dart';

const _newcardReferer = 'https://newcard.xjit.edu.cn/';

class PaymentWebViewPage extends StatefulWidget {
  const PaymentWebViewPage({
    super.key,
    required this.title,
    required this.payResult,
  });

  final String title;
  final Map<String, dynamic> payResult;

  @override
  State<PaymentWebViewPage> createState() => _PaymentWebViewPageState();
}

class _PaymentWebViewPageState extends State<PaymentWebViewPage> {
  late final WebViewController _controller;
  late final _PaymentEntry _entry;
  final Set<String> _refererLoadedUrls = {};
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _entry = _PaymentEntry.fromPayResult(widget.payResult);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _handleNavigationRequest,
          onPageStarted: (_) => _setLoading(true),
          onPageFinished: (_) {
            _setLoading(false);
          },
          onWebResourceError: (_) {
            _setLoading(false);
          },
        ),
      );

    unawaited(_loadPaymentEntry());
  }

  Future<void> _loadPaymentEntry() async {
    if (_entry.uri != null) {
      if (!_canOpenInWebView(_entry.uri!)) {
        final opened = await _openExternalUri(_entry.uri!);
        if (!opened) {
          _showExternalOpenFailure();
        }
        _setLoading(false);
        return;
      }
      final headers = _refererHeaders(_entry.uri!);
      if (headers.isNotEmpty) {
        _refererLoadedUrls.add(_entry.uri!.toString());
      }
      await _controller.loadRequest(_entry.uri!, headers: headers);
    } else {
      await _controller.loadHtmlString(
        _paymentHtml(_entry.htmlPost),
        baseUrl: _newcardReferer,
      );
    }
  }

  Future<NavigationDecision> _handleNavigationRequest(
    NavigationRequest request,
  ) async {
    final uri = Uri.tryParse(request.url);
    if (uri == null) {
      return NavigationDecision.navigate;
    }

    if (_shouldAttachReferer(uri) &&
        !_refererLoadedUrls.contains(uri.toString())) {
      _refererLoadedUrls.add(uri.toString());
      unawaited(_controller.loadRequest(uri, headers: _refererHeaders(uri)));
      return NavigationDecision.prevent;
    }

    if (_canOpenInWebView(uri)) {
      return NavigationDecision.navigate;
    }

    final opened = await _openExternalUri(uri);
    if (!opened) {
      _showExternalOpenFailure();
    }
    return NavigationDecision.prevent;
  }

  Future<bool> _openExternalUri(Uri uri) async {
    if (uri.scheme.toLowerCase() == 'intent') {
      return _openAndroidIntentUri(uri);
    }

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _openAndroidIntentUri(Uri uri) async {
    final targetUri = _intentTargetUri(uri);
    if (targetUri != null && await _openExternalUri(targetUri)) {
      return true;
    }

    final fallbackUri = _intentFallbackUri(uri);
    if (fallbackUri == null) {
      return false;
    }

    if (_canOpenInWebView(fallbackUri)) {
      await _controller.loadRequest(
        fallbackUri,
        headers: _refererHeaders(fallbackUri),
      );
      return true;
    }
    return _openExternalUri(fallbackUri);
  }

  bool _canOpenInWebView(Uri uri) {
    switch (uri.scheme.toLowerCase()) {
      case 'http':
      case 'https':
      case 'about':
      case 'data':
      case 'file':
        return true;
    }
    return false;
  }

  bool _shouldAttachReferer(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return false;
    }
    final host = uri.host.toLowerCase();
    return _entry.needsReferer ||
        host == 'wx.tenpay.com' ||
        host.endsWith('.wx.tenpay.com');
  }

  Map<String, String> _refererHeaders(Uri uri) {
    return _shouldAttachReferer(uri)
        ? const {'Referer': _newcardReferer}
        : const <String, String>{};
  }

  Uri? _intentTargetUri(Uri uri) {
    final params = _intentParams(uri);
    final scheme = params['scheme'];
    if (scheme == null || scheme.isEmpty) {
      return null;
    }

    final rawUrl = uri.toString();
    final intentIndex = rawUrl.indexOf('#Intent;');
    final body = intentIndex >= 0
        ? rawUrl.substring('intent:'.length, intentIndex)
        : rawUrl.substring('intent:'.length);
    return Uri.tryParse('$scheme:$body');
  }

  Uri? _intentFallbackUri(Uri uri) {
    final fallback = _intentParams(uri)['S.browser_fallback_url'];
    if (fallback == null || fallback.isEmpty) {
      return null;
    }
    try {
      return Uri.tryParse(Uri.decodeComponent(fallback));
    } catch (_) {
      return Uri.tryParse(fallback);
    }
  }

  Map<String, String> _intentParams(Uri uri) {
    final result = <String, String>{};
    for (final part in uri.fragment.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      result[part.substring(0, separator)] = part.substring(separator + 1);
    }
    return result;
  }

  void _setLoading(bool value) {
    if (mounted && _loading != value) {
      setState(() => _loading = value);
    }
  }

  void _showExternalOpenFailure() {
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有找到可打开支付链接的应用')));
    });
  }

  String _paymentHtml(String htmlPost) {
    if (htmlPost.trim().isEmpty) {
      return '<!doctype html><html><body><p>支付入口为空</p></body></html>';
    }
    if (htmlPost.toLowerCase().contains('<html')) {
      return htmlPost;
    }
    return '''
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
</head>
<body>
  $htmlPost
  <script>
    setTimeout(function() {
      var form = document.forms[0];
      if (form) { form.submit(); }
    }, 80);
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

class _PaymentEntry {
  const _PaymentEntry({
    required this.uri,
    required this.htmlPost,
    required this.needsReferer,
  });

  final Uri? uri;
  final String htmlPost;
  final bool needsReferer;

  factory _PaymentEntry.fromPayResult(Map<String, dynamic> payResult) {
    final officialTransferUrl = textValue(
      payResult['officialTransferUrl'],
      fallback: '',
    );
    final h5Url = textValue(payResult['h5Url'], fallback: '');
    final htmlPost = textValue(payResult['htmlPost'], fallback: '');
    final payCode = textValue(payResult['payCode'], fallback: '');
    final source = '$officialTransferUrl $h5Url $htmlPost'.toLowerCase();
    final isWechatPay =
        payCode == '02' ||
        source.contains('wx.tenpay.com') ||
        source.contains('weixin') ||
        source.contains('wechat');

    final officialUri = Uri.tryParse(officialTransferUrl);
    if (_isUsableUri(officialUri)) {
      return _PaymentEntry(
        uri: officialUri,
        htmlPost: htmlPost,
        needsReferer: isWechatPay,
      );
    }

    final h5Uri = Uri.tryParse(h5Url);
    if (_isUsableUri(h5Uri)) {
      return _PaymentEntry(uri: h5Uri, htmlPost: htmlPost, needsReferer: true);
    }

    return _PaymentEntry(uri: null, htmlPost: htmlPost, needsReferer: false);
  }

  static bool _isUsableUri(Uri? uri) {
    return uri != null && uri.scheme.isNotEmpty;
  }
}
