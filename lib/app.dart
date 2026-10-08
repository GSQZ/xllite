import 'package:flutter/material.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import 'features/auth/presentation/auth_gate.dart';
import 'features/auth/presentation/auth_web_view.dart';
import 'shared/theme/app_theme.dart';
import 'shared/theme/theme_settings.dart';

class XinliApp extends StatefulWidget {
  const XinliApp({
    super.key,
    this.createController = createAuthController,
    this.createCampus = createCampusController,
    this.webViewBuilder = buildPlatformAuthWebView,
    this.launchExternal = launchExternalUrl,
    this.themeSettings,
  });

  /// Called once by the root State. Tests inject a fake-backed controller.
  final AuthController Function() createController;

  /// Business services sharing the auth controller's lifetime.
  final CampusController Function(AuthController auth) createCampus;
  final AuthWebViewBuilder webViewBuilder;
  final ExternalUrlLauncher launchExternal;

  /// Loaded before the first frame by main(); in-memory defaults otherwise.
  final ThemeSettings? themeSettings;


  @override
  State<XinliApp> createState() => _XinliAppState();
}

class _XinliAppState extends State<XinliApp> with WidgetsBindingObserver {
  late final AuthController _auth;
  late final CampusController _campus;
  late final ThemeSettings _theme =
      widget.themeSettings ?? ThemeSettings(MemoryThemeStore());

  @override
  void initState() {
    super.initState();
    _auth = widget.createController();
    _campus = widget.createCampus(_auth);
    WidgetsBinding.instance.addObserver(this);
    _auth.restore();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    // The payment code drops its credential whenever the app leaves the
    // foreground; the controller decides whether a token needs renewing.
    _campus.campusCode.setForeground(resumed);
    if (resumed) _auth.refreshSession();
  }


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _campus.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      settings: _theme,
      child: ListenableBuilder(
        listenable: _theme,
        // MaterialApp cross-fades between themes on its own.
        builder: (context, _) => MaterialApp(
          title: '新理Lite',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(seed: _theme.skin.color),
          darkTheme: AppTheme.dark(seed: _theme.skin.color),
          themeMode: _theme.mode,
          themeAnimationDuration: AppMotion.long,
          themeAnimationCurve: AppMotion.emphasized,
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            maxScaleFactor: 2,
            child: child!,
          ),
          home: AuthGate(
            controller: _auth,
            campus: _campus,
            webViewBuilder: widget.webViewBuilder,
            launchExternal: widget.launchExternal,
          ),
        ),
      ),
    );
  }
}
