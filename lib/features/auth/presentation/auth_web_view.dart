import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class AuthNavigationRequest {
  const AuthNavigationRequest({required this.url, required this.isMainFrame});

  final String url;
  final bool isMainFrame;
}

/// What the WeChat page needs from a WebView. Navigation policy lives in the
/// page; the adapter only forwards platform events.
class AuthWebViewConfig {
  const AuthWebViewConfig({
    required this.initialUrl,
    required this.shouldAllowNavigation,
    required this.onUrlChanged,
    required this.onProgress,
    required this.onMainFrameError,
  });

  final Uri initialUrl;

  /// Return false to block the navigation.
  final FutureOr<bool> Function(AuthNavigationRequest request)
  shouldAllowNavigation;
  final ValueChanged<String> onUrlChanged;
  final ValueChanged<int> onProgress;
  final VoidCallback onMainFrameError;
}

typedef AuthWebViewBuilder =
    Widget Function(BuildContext context, AuthWebViewConfig config);

typedef ExternalUrlLauncher = Future<bool> Function(Uri uri);

Widget buildPlatformAuthWebView(
  BuildContext context,
  AuthWebViewConfig config,
) => PlatformAuthWebView(config: config);

Future<bool> launchExternalUrl(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// webview_flutter implementation. Give it a new key to reload from scratch.
class PlatformAuthWebView extends StatefulWidget {
  const PlatformAuthWebView({super.key, required this.config});

  final AuthWebViewConfig config;

  @override
  State<PlatformAuthWebView> createState() => _PlatformAuthWebViewState();
}

class _PlatformAuthWebViewState extends State<PlatformAuthWebView> {
  late final WebViewController _controller;

  // iOS reports a cancelled policy decision (our own "prevent") as an error.
  static const _cancelledCodes = {-999, 102};

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            final allow = await widget.config.shouldAllowNavigation(
              AuthNavigationRequest(
                url: request.url,
                isMainFrame: request.isMainFrame,
              ),
            );
            return allow
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) widget.config.onUrlChanged(url);
          },
          onProgress: (progress) => widget.config.onProgress(progress),
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) return;
            if (_cancelledCodes.contains(error.errorCode)) return;
            widget.config.onMainFrameError();
          },
        ),
      )
      ..loadRequest(widget.config.initialUrl);
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
