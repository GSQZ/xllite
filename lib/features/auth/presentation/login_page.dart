import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xinli_lite/features/auth/auth.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/adaptive_page_body.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/brand_mark.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/status_banner.dart';
import 'auth_recovery.dart';
import 'auth_web_view.dart';
import 'wechat_login_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.controller,
    this.recovery = AuthRecovery.none,
    this.webViewBuilder = buildPlatformAuthWebView,
    this.launchExternal = launchExternalUrl,
  });

  final AuthController controller;
  final AuthRecovery recovery;
  final AuthWebViewBuilder webViewBuilder;
  final ExternalUrlLauncher launchExternal;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  late final _entrance = AnimationController(
    vsync: this,
    duration: AppMotion.entrance,
  );
  late final _shake = AnimationController(
    vsync: this,
    duration: AppMotion.shake,
  );
  late AuthPhase _lastPhase = widget.controller.state.phase;
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  var _obscurePassword = true;
  var _autovalidate = AutovalidateMode.disabled;

  AuthController get _auth => widget.controller;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
  }

  @override
  void didUpdateWidget(LoginPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onAuthChanged);
      widget.controller.addListener(_onAuthChanged);
    }
  }

  void _onAuthChanged() {
    final state = _auth.state;
    final rejected =
        _lastPhase == AuthPhase.signingIn &&
        state.phase == AuthPhase.signedOut &&
        state.failure != null;
    _lastPhase = state.phase;
    if (rejected) _signalError();
  }

  /// Shake + haptic for a rejected attempt; haptic only under reduce motion.
  void _signalError() {
    HapticFeedback.mediumImpact();
    if (!mounted || AppMotion.reduced(context)) return;
    _shake.forward(from: 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entrance.isDismissed) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _entrance.value = 1;
      } else {
        _entrance.forward();
      }
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _entrance.dispose();
    _shake.dispose();
    _username.dispose();
    _password.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_auth.state.isBusy) return;
    setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
    if (!_formKey.currentState!.validate()) {
      _signalError();
      (_username.text.trim().isEmpty ? _usernameFocus : _passwordFocus)
          .requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    // Password is passed exactly as typed: no trim, no copy kept elsewhere.
    _auth.signIn(username: _username.text, password: _password.text);
  }

  void _onEdited(String _) {
    // A form error is stale once the user edits; recovery prompts stay.
    if (widget.recovery == AuthRecovery.none) _auth.clearFailure();
  }

  void _openWechat() {
    if (_auth.state.isBusy) return;
    FocusScope.of(context).unfocus();
    WechatLoginPage.open(
      context,
      controller: _auth,
      webViewBuilder: widget.webViewBuilder,
      launchExternal: widget.launchExternal,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Backdrop and status bar style come from AuthGate, shared by every
    // top-level screen so hand-offs never repaint the background.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _auth,
          builder: (context, _) => _buildBody(context, _auth.state),
        ),
      ),
    );
  }

  Widget _reveal(int step, Widget child) => StaggeredReveal(
    animation: _entrance,
    step: step,
    delay:
        AppMotion.entranceDelay.inMilliseconds /
        AppMotion.entrance.inMilliseconds,
    stepFraction: 0.08,
    window: 0.45,
    child: child,
  );

  Widget _buildBody(BuildContext context, AuthState state) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final submitting = state.phase == AuthPhase.signingIn;
    final locked = state.isBusy;

    // Lift the content on tall phones instead of floating it mid-screen;
    // short screens give that space back to the form.
    final height = MediaQuery.sizeOf(context).height;
    final compact = height < 700;
    final topGap = compact ? 0.0 : (height * 0.05).clamp(0.0, AppSpacing.xxxl);

    return AdaptivePageBody(
      footer: _reveal(4, const _Disclaimer()),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: topGap),
          _reveal(0, _Greeting(compact: compact)),
          SizedBox(
            height: compact ? AppSpacing.xl : AppSpacing.xxl + AppSpacing.xs,
          ),
          _reveal(
            1,
            ShakeTransition(
              animation: _shake,
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  autovalidateMode: _autovalidate,
                  child: Column(
                    key: const Key('login.form'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const Key('login.username'),
                        controller: _username,
                        focusNode: _usernameFocus,
                        enabled: !locked,
                        autofillHints: const [AutofillHints.username],
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        inputFormatters: [LengthLimitingTextInputFormatter(64)],
                        decoration: const InputDecoration(
                          labelText: '学号',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (value) =>
                            (value ?? '').trim().isEmpty ? '请输入学号' : null,
                        onChanged: _onEdited,
                        onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                      ),
                      const SizedBox(height: AppSpacing.md + 2),
                      TextFormField(
                        key: const Key('login.password'),
                        controller: _password,
                        focusNode: _passwordFocus,
                        enabled: !locked,
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.password],
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'CAS 密码',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: Padding(
                            padding: const EdgeInsetsDirectional.only(
                              end: AppSpacing.xs,
                            ),
                            child: IconButton(
                              key: const Key('login.togglePassword'),
                              tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                              onPressed: locked
                                  ? null
                                  : () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                              icon: AnimatedSwitcher(
                                duration: AppMotion.short,
                                child: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  key: ValueKey(_obscurePassword),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Empty check only; whitespace may be part of a password.
                        validator: (value) =>
                            (value ?? '').isEmpty ? '请输入 CAS 密码' : null,
                        onChanged: _onEdited,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.emphasized,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: AppMotion.medium,
              switchInCurve: AppMotion.curve,
              switchOutCurve: AppMotion.exit,
              transitionBuilder: fadeThroughTransition,
              child: _buildFailure(state),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _reveal(
            2,
            AppButton(
              key: const Key('login.submit'),
              label: '登录',
              loading: submitting,
              loadingLabel: '正在登录…',
              onPressed: locked ? null : _submit,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _reveal(
            3,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _OrDivider(color: scheme.onSurfaceVariant),
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  key: const Key('login.wechat'),
                  variant: AppButtonVariant.outlined,
                  icon: Icons.qr_code_scanner_rounded,
                  iconColor: StatusColors.of(context).success,
                  label: '微信扫码登录',
                  onPressed: locked ? null : _openWechat,
                ),
              ],
            ),
          ),
        ],
      ),
      child: const SizedBox.shrink(),
    );
  }

  Widget _buildFailure(AuthState state) {
    final failure = state.failure;
    final retryingSignOut =
        widget.recovery == AuthRecovery.signOut &&
        state.phase == AuthPhase.signingOut;
    if (failure == null && !retryingSignOut) {
      return const SizedBox(key: ValueKey('none'), width: double.infinity);
    }
    final banner = switch (widget.recovery) {
      AuthRecovery.signOut => StatusBanner(
        title: '退出未完成',
        message: failure == null
            ? '正在重新清除本机登录信息…'
            : '${failure.message}\n本机可能仍保留登录信息，请重试退出。',
        actionLabel: '重试退出',
        actionBusy: retryingSignOut,
        onAction: () => _auth.signOut(),
      ),
      AuthRecovery.restore => StatusBanner(
        tone: StatusTone.warning,
        title: '未能恢复登录',
        message: failure?.message ?? '',
        actionLabel: '重试',
        onAction: () => _auth.restore(),
        onDismiss: () => _auth.clearFailure(),
      ),
      AuthRecovery.none => StatusBanner(
        key: const Key('login.error'),
        message: failure?.message ?? '',
      ),
    };
    return Padding(
      key: ValueKey((widget.recovery, failure?.message)),
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: banner,
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BrandMark(size: compact ? 48 : 56),
        SizedBox(
          height: compact ? AppSpacing.lg : AppSpacing.xl + AppSpacing.xs,
        ),
        // Two wrap units, so a narrow screen breaks between them rather than
        // inside the product name.
        Semantics(
          header: true,
          label: '欢迎使用新理Lite',
          excludeSemantics: true,
          child: Wrap(
            children: [
              for (final part in const ['欢迎使用', '新理Lite'])
                Text(
                  part,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: compact ? 24 : 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '使用新疆理工学院统一身份认证账号登录',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final line = Divider(color: color.withValues(alpha: 0.18));
    return Row(
      children: [
        Expanded(child: line),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            '其他登录方式',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
        Expanded(child: line),
      ],
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Column(
      children: [
        Text(
          '民间开发版本，不代表学校官方应用',
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          '密码经服务端转交学校认证，客户端仅保存登录令牌',
          style: theme.textTheme.bodySmall?.copyWith(color: color),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
