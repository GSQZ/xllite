import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/soft_backdrop.dart';
import '../../campus/presentation/home_shell.dart';
import 'auth_recovery.dart';
import 'auth_web_view.dart';
import 'login_page.dart';
import 'restoring_page.dart';

/// Chooses the top-level screen from [AuthController.state].
///
/// Page switches are driven only by phase changes, never by method return
/// values. Crossing the signed-in boundary clears any pushed routes (such as
/// the WeChat page) so nothing lingers above the new screen.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.controller,
    required this.campus,
    this.webViewBuilder = buildPlatformAuthWebView,
    this.launchExternal = launchExternalUrl,
  });

  final AuthController controller;
  final CampusController campus;
  final AuthWebViewBuilder webViewBuilder;
  final ExternalUrlLauncher launchExternal;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

enum _Screen { restoring, login, home }

class _AuthGateState extends State<AuthGate> {
  late _Screen _screen;
  AuthRecovery _recovery = AuthRecovery.none;

  @override
  void initState() {
    super.initState();
    final state = widget.controller.state;
    _recovery = _recoveryFor(state);
    _screen = _screenFor(state.phase, _Screen.restoring);
    widget.controller.addListener(_onAuthChanged);
  }

  @override
  void didUpdateWidget(AuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onAuthChanged);
      widget.controller.addListener(_onAuthChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onAuthChanged);
    super.dispose();
  }

  static _Screen _screenFor(AuthPhase phase, _Screen current) =>
      switch (phase) {
        AuthPhase.idle || AuthPhase.restoring => _Screen.restoring,
        AuthPhase.authenticated => _Screen.home,
        // Retrying a failed sign-out from the login screen stays there.
        AuthPhase.signingOut =>
          current == _Screen.home ? _Screen.home : _Screen.login,
        _ => _Screen.login,
      };

  static AuthRecovery _recoveryFor(AuthState state) {
    if (state.phase != AuthPhase.signedOut || state.failure == null) {
      return AuthRecovery.none;
    }
    return switch (state.failure!.operation) {
      AuthOperation.restore => AuthRecovery.restore,
      AuthOperation.signOut => AuthRecovery.signOut,
      _ => AuthRecovery.none,
    };
  }

  void _onAuthChanged() {
    final state = widget.controller.state;

    if (state.phase != AuthPhase.restoring &&
        state.phase != AuthPhase.signingOut) {
      _recovery = _recoveryFor(state);
    }

    final next = _screenFor(state.phase, _screen);
    final crossedBoundary = (next == _Screen.home) != (_screen == _Screen.home);
    if (crossedBoundary) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    if (next != _screen) setState(() => _screen = next);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final Widget page = switch (_screen) {
          _Screen.restoring => const RestoringPage(key: ValueKey('restoring')),
          _Screen.login => LoginPage(
            key: const ValueKey('login'),
            controller: widget.controller,
            recovery: _recovery,
            webViewBuilder: widget.webViewBuilder,
            launchExternal: widget.launchExternal,
          ),
          _Screen.home => HomeShell(
            key: const ValueKey('home'),
            auth: widget.controller,
            campus: widget.campus,
          ),
        };
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(statusBarColor: Colors.transparent),
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: SoftBackdrop(
              child: AnimatedSwitcher(
                duration: AppMotion.reduced(context)
                    ? Duration.zero
                    : AppMotion.handoff,
                // Curves live inside handoffTransition.
                transitionBuilder: handoffTransition,
                child: page,
              ),
            ),
          ),
        );
      },
    );
  }
}
