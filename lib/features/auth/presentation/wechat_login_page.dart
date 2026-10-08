import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xinli_lite/features/auth/auth.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/state_panel.dart';
import '../../../shared/widgets/status_banner.dart';
import 'auth_web_view.dart';

/// WeChat QR login. The controller owns polling, expiry and ticket exchange;
/// this page only hosts the authorization WebView and reflects state.
class WechatLoginPage extends StatefulWidget {
  const WechatLoginPage({
    super.key,
    required this.controller,
    this.webViewBuilder = buildPlatformAuthWebView,
    this.launchExternal = launchExternalUrl,
  });

  final AuthController controller;
  final AuthWebViewBuilder webViewBuilder;
  final ExternalUrlLauncher launchExternal;

  /// External schemes the authorization page may hand off to.
  static const allowedExternalSchemes = {'weixin'};

  /// Starts a challenge from the caller's event handler (never from build or
  /// initState) and presents the page.
  static Future<void> open(
    BuildContext context, {
    required AuthController controller,
    AuthWebViewBuilder webViewBuilder = buildPlatformAuthWebView,
    ExternalUrlLauncher launchExternal = launchExternalUrl,
  }) {
    controller.startWechat();
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => WechatLoginPage(
          controller: controller,
          webViewBuilder: webViewBuilder,
          launchExternal: launchExternal,
        ),
      ),
    );
  }

  @override
  State<WechatLoginPage> createState() => _WechatLoginPageState();
}

class _WechatLoginPageState extends State<WechatLoginPage> {
  Timer? _ticker;
  int _progress = 0;
  bool _loadFailed = false;
  int _reloadCount = 0;
  WechatChallenge? _challenge;

  AuthController get _auth => widget.controller;

  static const _wechatPhases = {
    AuthPhase.wechatStarting,
    AuthPhase.wechatPending,
    AuthPhase.wechatCompleting,
  };

  @override
  void initState() {
    super.initState();
    _challenge = _auth.state.challenge;
    _auth.addListener(_onAuthChanged);
    // Repaints the countdown; expiry itself is decided by the controller.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _auth.state.challenge != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _auth.removeListener(_onAuthChanged);
    // Safety net for removals that bypass PopScope. Deferred so the
    // controller never notifies while the tree is being finalized.
    if (_wechatPhases.contains(_auth.state.phase)) {
      final auth = _auth;
      scheduleMicrotask(auth.cancelWechat);
    }
    super.dispose();
  }

  void _onAuthChanged() {
    final challenge = _auth.state.challenge;
    if (identical(challenge, _challenge)) return;
    // Each challenge gets a fresh WebView (keyed by the challenge object).
    setState(() {
      _challenge = challenge;
      _loadFailed = false;
      _progress = 0;
    });
  }

  void _onPopped() {
    _auth.cancelWechat();
    // A QR failure means nothing on the password form.
    if (_auth.state.phase == AuthPhase.signedOut) _auth.clearFailure();
  }

  void _retry() => _auth.startWechat();

  void _reloadPage() {
    setState(() {
      _loadFailed = false;
      _progress = 0;
      _reloadCount++;
    });
  }

  void _usePassword() => Navigator.of(context).maybePop();

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  FutureOr<bool> _shouldAllowNavigation(AuthNavigationRequest request) {
    final url = request.url;
    final challenge = _auth.state.challenge;
    // The ticket must reach our backend, never the service page: CAS tickets
    // are single-use. ticketFromRedirect also checks this challenge's state.
    if (challenge != null && challenge.ticketFromRedirect(url) != null) {
      unawaited(_auth.handleWechatRedirect(url));
      return false;
    }
    final uri = Uri.tryParse(url);
    final scheme = uri?.scheme.toLowerCase() ?? '';
    if (scheme == 'https') return true;
    if (scheme == 'about' && (uri!.path == 'blank' || uri.path == 'srcdoc')) {
      return true;
    }
    if (WechatLoginPage.allowedExternalSchemes.contains(scheme)) {
      unawaited(_openExternal(uri!));
      return false;
    }
    if (request.isMainFrame) _notify('已阻止不受支持的页面跳转');
    return false;
  }

  Future<void> _openExternal(Uri uri) async {
    final opened = await widget.launchExternal(uri);
    if (!opened) _notify('未能打开微信，请确认已安装微信，或使用另一台设备扫码');
  }

  void _onUrlChanged(String url) {
    // Fallback for URL changes that skip the navigation callback (e.g. hash
    // routing). The controller ignores duplicates and unrelated URLs.
    final challenge = _auth.state.challenge;
    if (challenge != null && challenge.ticketFromRedirect(url) != null) {
      unawaited(_auth.handleWechatRedirect(url));
    }
  }

  void _onProgress(int progress) {
    if (mounted && progress != _progress) setState(() => _progress = progress);
  }

  void _onMainFrameError() {
    if (!mounted || _auth.state.phase != AuthPhase.wechatPending) return;
    setState(() => _loadFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _onPopped();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close_rounded),
            onPressed: _usePassword,
          ),
          title: const Text('微信扫码登录'),
        ),
        body: ListenableBuilder(
          listenable: _auth,
          builder: (context, _) {
            final state = _auth.state;
            return AnimatedSwitcher(
              duration: AppMotion.reduced(context)
                  ? Duration.zero
                  : AppMotion.long,
              switchInCurve: AppMotion.curve,
              switchOutCurve: AppMotion.exit,
              transitionBuilder: fadeThroughTransition,
              child: KeyedSubtree(
                key: ValueKey(_bodyKind(state)),
                child: _buildBody(context, state),
              ),
            );
          },
        ),
      ),
    );
  }

  String _bodyKind(AuthState state) => switch (state.phase) {
    AuthPhase.wechatPending ||
    AuthPhase.wechatCompleting when state.challenge != null => 'challenge',
    AuthPhase.wechatStarting => 'starting',
    AuthPhase.authenticated => 'done',
    _ => state.failure == null ? 'idle' : 'failure',
  };

  Widget _buildBody(BuildContext context, AuthState state) {
    final challenge = state.challenge;
    switch (state.phase) {
      case AuthPhase.wechatPending || AuthPhase.wechatCompleting
          when challenge != null:
        return _buildChallenge(context, state, challenge);
      case AuthPhase.wechatStarting:
        return const SafeArea(
          child: StatePanel(loading: true, title: '正在获取扫码入口…'),
        );
      case AuthPhase.authenticated:
        return const SafeArea(
          child: StatePanel(icon: Icons.check_rounded, title: '登录成功'),
        );
      default:
        return SafeArea(child: _buildFailure(state.failure));
    }
  }

  Widget _buildFailure(AuthFailure? failure) {
    final expired = failure?.kind == AuthFailureKind.expired;
    return StatePanel(
      key: const Key('wechat.failure'),
      icon: failure == null
          ? Icons.qr_code_2_rounded
          : expired
          ? Icons.timer_off_outlined
          : Icons.error_outline_rounded,
      tone: failure == null || expired ? PanelTone.neutral : PanelTone.error,
      title: failure == null
          ? '扫码登录'
          : expired
          ? '二维码已过期'
          : '扫码登录未完成',
      message: failure?.message ?? '获取二维码后，请使用另一台设备上的微信扫码。',
      actions: [
        AppButton(
          key: const Key('wechat.retry'),
          icon: Icons.refresh_rounded,
          label: failure == null ? '获取二维码' : '重新获取二维码',
          onPressed: _retry,
        ),
        AppButton(
          variant: AppButtonVariant.outlined,
          label: '改用账号密码登录',
          onPressed: _usePassword,
        ),
      ],
    );
  }

  Widget _buildChallenge(
    BuildContext context,
    AuthState state,
    WechatChallenge challenge,
  ) {
    final completing = state.phase == AuthPhase.wechatCompleting;
    final pageLoading = _progress < 100 && !_loadFailed && !completing;
    final failure = state.failure;
    final remaining = challenge.expiresAt.difference(DateTime.now());
    final gutter = AppSpacing.gutterFor(MediaQuery.sizeOf(context).width);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, AppSpacing.sm),
          child: _CountdownRow(remaining: remaining),
        ),
        if (failure != null)
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, AppSpacing.sm),
            child: StatusBanner(
              tone: StatusTone.warning,
              title: '正在自动重试',
              message: failure.message,
            ),
          ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              KeyedSubtree(
                key: ValueKey((challenge, _reloadCount)),
                child: widget.webViewBuilder(
                  context,
                  AuthWebViewConfig(
                    initialUrl: challenge.authUrl,
                    shouldAllowNavigation: _shouldAllowNavigation,
                    onUrlChanged: _onUrlChanged,
                    onProgress: _onProgress,
                    onMainFrameError: _onMainFrameError,
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: pageLoading ? 1 : 0,
                duration: AppMotion.medium,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    // Indeterminate only while visible, so a hidden bar
                    // never keeps animating.
                    value: pageLoading && _progress == 0
                        ? null
                        : _progress / 100,
                    semanticsLabel: '授权页面加载中',
                  ),
                ),
              ),
              if (_loadFailed && !completing)
                ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: StatePanel(
                    key: const Key('wechat.loadFailed'),
                    icon: Icons.cloud_off_rounded,
                    tone: PanelTone.error,
                    title: '授权页面加载失败',
                    message: '请检查网络连接后重试。',
                    actions: [
                      AppButton(
                        label: '重新加载',
                        icon: Icons.refresh_rounded,
                        onPressed: _reloadPage,
                      ),
                    ],
                  ),
                ),
              AnimatedSwitcher(
                duration: AppMotion.medium,
                switchInCurve: AppMotion.curve,
                switchOutCurve: AppMotion.exit,
                child: !completing
                    ? const SizedBox.shrink()
                    : Semantics(
                        container: true,
                        child: ColoredBox(
                          key: const Key('wechat.completing'),
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withValues(alpha: 0.94),
                          child: const StatePanel(
                            loading: true,
                            title: '正在确认登录…',
                            message: '已收到扫码结果，请稍候，不要关闭此页面。',
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        _ScanHint(gutter: gutter, onUsePassword: _usePassword),
      ],
    );
  }
}

class _CountdownRow extends StatelessWidget {
  const _CountdownRow({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    final seconds = remaining.inSeconds.clamp(0, 86400);
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    final urgent = seconds < 60;
    final color = urgent ? status.warning : theme.colorScheme.onSurfaceVariant;
    final clock =
        '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';

    return Semantics(
      label: '二维码剩余有效时间 $minutes 分 $rest 秒',
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              '二维码 $clock 后失效',
              key: const Key('wechat.countdown'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanHint extends StatelessWidget {
  const _ScanHint({required this.gutter, required this.onUsePassword});

  final double gutter;
  final VoidCallback onUsePassword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        // Large fonts on small phones must not squeeze the WebView to nothing.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.26,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              gutter,
              AppSpacing.md,
              gutter,
              AppSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('请用另一台设备上的微信扫码', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '受微信限制，在同一台手机上截图或长按识别二维码无法完成登录。'
                  '扫码并在微信中确认后，本页会自动完成登录。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Transform.translate(
                  offset: const Offset(-AppSpacing.md, 0),
                  child: TextButton.icon(
                    key: const Key('wechat.usePassword'),
                    onPressed: onUsePassword,
                    icon: const Icon(Icons.password_rounded, size: 18),
                    label: const Text('改用账号密码登录'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
