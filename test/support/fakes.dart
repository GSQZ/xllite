import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/app.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/auth/presentation/auth_web_view.dart';
import 'package:xinli_lite/features/campus/campus.dart';
import 'package:xinli_lite/shared/theme/theme_settings.dart';

import 'campus_fakes.dart';

const testToken = 'secret-access-token';

AuthSession testSession({
  String username = '20230001',
  Duration lifetime = const Duration(hours: 2),
}) => AuthSession(
  accessToken: testToken,
  username: username,
  source: 'password',
  expiresAt: DateTime.now().add(lifetime),
);

WechatChallenge testChallenge({String state = 'state-1'}) => WechatChallenge(
  state: state,
  authUrl: Uri.parse('https://cas.xjit.edu.cn/lyuapServer/login?wechat=1'),
  serviceUrl: Uri.parse('https://superapp.xjit.edu.cn/app'),
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
);

String redirectFor(WechatChallenge challenge, {String ticket = 'ST-1'}) =>
    'https://superapp.xjit.edu.cn/app?ticket=$ticket'
    '&xjitApiState=${challenge.state}';

typedef SignInCall = ({String username, String password, String? captcha});

/// In-memory [AuthRepository]. Each hook defaults to an instant success;
/// tests swap in Completers to hold a request open.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.stored});

  AuthSession? stored;
  Future<AuthSession?> Function()? onRead;
  Future<AuthSession> Function(SignInCall call)? onSignIn;
  Future<AuthSession> Function(AuthSession session)? onRefresh;
  Future<WechatChallenge> Function()? onStartWechat;
  Future<WechatResult> Function()? onCheckWechat;
  Future<WechatResult> Function(String ticket)? onCompleteWechat;
  Future<void> Function()? onClear;

  /// Number of upcoming clearSession() calls that fail like a keychain error.
  int clearFailures = 0;

  final signInCalls = <SignInCall>[];
  int readCalls = 0;
  int refreshCalls = 0;
  int clearCalls = 0;
  int startWechatCalls = 0;
  int checkWechatCalls = 0;
  final completedTickets = <String>[];

  @override
  Future<AuthSession?> readSession() {
    readCalls++;
    return onRead?.call() ?? Future.value(stored);
  }

  @override
  Future<void> saveSession(AuthSession session) async => stored = session;

  @override
  Future<void> clearSession() async {
    clearCalls++;
    await onClear?.call();
    if (clearFailures > 0) {
      clearFailures--;
      throw const AuthFailure(AuthFailureKind.storage, '无法清除本机登录信息');
    }
    stored = null;
  }

  @override
  Future<AuthSession> signIn({
    required String username,
    required String password,
    String? captcha,
  }) {
    final call = (username: username, password: password, captcha: captcha);
    signInCalls.add(call);
    return onSignIn?.call(call) ??
        Future.value(testSession(username: username));
  }

  @override
  Future<AuthSession> refresh(AuthSession session) {
    refreshCalls++;
    return onRefresh?.call(session) ?? Future.value(testSession());
  }

  @override
  Future<void> revoke(AuthSession session) async {}

  @override
  Future<WechatChallenge> startWechat() {
    startWechatCalls++;
    return onStartWechat?.call() ?? Future.value(testChallenge());
  }

  @override
  Future<WechatResult> checkWechat(WechatChallenge challenge) {
    checkWechatCalls++;
    return onCheckWechat?.call() ??
        Future.value(const WechatResult(WechatStatus.pending));
  }

  @override
  Future<WechatResult> completeWechat(
    WechatChallenge challenge, {
    required String ticket,
  }) {
    completedTickets.add(ticket);
    return onCompleteWechat?.call(ticket) ??
        Future.value(
          WechatResult(WechatStatus.success, session: testSession()),
        );
  }
}

/// Stands in for the platform WebView and exposes the page's callbacks.
class FakeWebViews {
  AuthWebViewConfig? config;
  int created = 0;

  Widget build(BuildContext context, AuthWebViewConfig config) {
    this.config = config;
    return _FakeWebView(host: this, url: config.initialUrl);
  }

  /// Simulates the WebView asking whether it may navigate.
  Future<bool> navigate(String url, {bool isMainFrame = true}) async =>
      config!.shouldAllowNavigation(
        AuthNavigationRequest(url: url, isMainFrame: isMainFrame),
      );
}

class _FakeWebView extends StatefulWidget {
  const _FakeWebView({required this.host, required this.url});

  final FakeWebViews host;
  final Uri url;

  @override
  State<_FakeWebView> createState() => _FakeWebViewState();
}

class _FakeWebViewState extends State<_FakeWebView> {
  @override
  void initState() {
    super.initState();
    widget.host.created++;
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    key: const Key('fake.webview'),
    color: const Color(0xFFEFEFEF),
    child: Center(child: Text(widget.url.host)),
  );
}

class TestApp {
  TestApp(
    this.repository, {
    UiCampusRepository? campusRepository,
    this.theme,
    this.widgetHost,
  }) : campusRepository = campusRepository ?? UiCampusRepository();

  final FakeAuthRepository repository;
  final UiCampusRepository campusRepository;

  /// In-memory appearance settings; see [pumpTestApp].
  final ThemeSettings? theme;

  /// Home-screen widget sink; kept in memory instead of a real platform.
  final WidgetHost? widgetHost;
  late CampusController campus;
  final webViews = FakeWebViews();
  final launchedUrls = <Uri>[];
  bool launchSucceeds = true;
  late AuthController controller;

  Widget build() => XinliApp(
    createController: () => controller = AuthController(repository: repository),
    createCampus: (auth) =>
        campus = CampusController(auth: auth, repository: campusRepository),
    themeSettings: theme,
    widgetHost: widgetHost,
    webViewBuilder: webViews.build,
    launchExternal: (uri) async {
      launchedUrls.add(uri);
      return launchSucceeds;
    },
  );
}

/// Pumps the app and waits for restore() to settle.
Future<TestApp> pumpTestApp(
  WidgetTester tester, {
  FakeAuthRepository? repository,
  UiCampusRepository? campusRepository,
  ThemeSettings? themeSettings,
  WidgetHost? widgetHost,
  bool settle = true,
}) async {
  final app = TestApp(
    repository ?? FakeAuthRepository(),
    campusRepository: campusRepository,
    theme: themeSettings,
    widgetHost: widgetHost,
  );
  await tester.pumpWidget(app.build());
  if (settle) await tester.pumpAndSettle();
  return app;
}

/// Advances past route/switcher transitions without waiting for spinners.
Future<void> pumpTransitions(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Simulates a small phone (iPhone SE 1st gen) with optional keyboard and
/// enlarged system text.
void useSmallScreen(
  WidgetTester tester, {
  double textScale = 1,
  double keyboardHeight = 0,
}) {
  const ratio = 2.0;
  tester.view.devicePixelRatio = ratio;
  tester.view.physicalSize = const Size(320 * ratio, 568 * ratio);
  tester.view.padding = const FakeViewPadding(top: 20 * ratio);
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight * ratio);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
}

/// The page-level scroll view (text fields contain their own Scrollables).
Finder get pageScrollable => find.byType(Scrollable).first;

/// The password form; present only while the login screen is shown.
Finder get loginForm => find.byKey(const Key('login.form'));
