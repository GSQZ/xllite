import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/auth/presentation/wechat_login_page.dart';

import '../support/campus_fakes.dart';
import '../support/fakes.dart';

Future<TestApp> _openWechat(
  WidgetTester tester, {
  FakeAuthRepository? repository,
}) async {
  final app = await pumpTestApp(tester, repository: repository);
  final button = find.byKey(const Key('login.wechat'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await pumpTransitions(tester);
  return app;
}

/// Finishes the fake page load so the indeterminate bar stops animating.
Future<void> _loaded(WidgetTester tester, TestApp app) async {
  app.webViews.config!.onProgress(100);
  await tester.pump();
}

void main() {
  testWidgets('shows a loading state, then the authorization WebView', (
    tester,
  ) async {
    final start = Completer<WechatChallenge>();
    final repo = FakeAuthRepository()..onStartWechat = () => start.future;
    final app = await _openWechat(tester, repository: repo);

    expect(find.byType(WechatLoginPage), findsOneWidget);
    expect(find.text('正在获取扫码入口…'), findsOneWidget);
    expect(find.byKey(const Key('fake.webview')), findsNothing);

    final challenge = testChallenge();
    start.complete(challenge);
    await pumpTransitions(tester);
    await _loaded(tester, app);

    expect(find.byKey(const Key('fake.webview')), findsOneWidget);
    expect(app.webViews.config!.initialUrl, challenge.authUrl);
    expect(find.textContaining('后失效'), findsOneWidget);
    expect(find.text('请用另一台设备上的微信扫码'), findsOneWidget);
    expect(find.textContaining('同一台手机上截图'), findsOneWidget);
    expect(find.byKey(const Key('wechat.usePassword')), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
  });

  testWidgets(
    'navigation policy: https allowed, others blocked or handed off',
    (tester) async {
      final app = await _openWechat(tester);
      await _loaded(tester, app);
      final web = app.webViews;

      expect(
        await web.navigate('https://open.weixin.qq.com/connect/qr'),
        isTrue,
      );
      expect(await web.navigate('about:blank', isMainFrame: false), isTrue);
      expect(await web.navigate('http://cas.xjit.edu.cn/login'), isFalse);
      expect(await web.navigate('alipays://platformapi'), isFalse);
      await tester.pump();
      expect(find.text('已阻止不受支持的页面跳转'), findsOneWidget);

      expect(await web.navigate('weixin://dl/business/?t=abc'), isFalse);
      await tester.pump();
      expect(app.launchedUrls.single.scheme, 'weixin');

      app.launchSucceeds = false;
      expect(await web.navigate('weixin://dl/business/?t=abc'), isFalse);
      await tester.pump();
      expect(find.textContaining('未能打开微信'), findsOneWidget);

      // A redirect carrying another session's state is not ours to intercept.
      final foreign = redirectFor(testChallenge(state: 'other'));
      expect(await web.navigate(foreign), isTrue);
      expect(app.repository.completedTickets, isEmpty);
    },
  );

  testWidgets('matching redirect is blocked, confirmed, then the page closes', (
    tester,
  ) async {
    final complete = Completer<WechatResult>();
    final repo = FakeAuthRepository()
      ..onCompleteWechat = (_) => complete.future;
    final app = await _openWechat(tester, repository: repo);
    await _loaded(tester, app);
    final challenge = app.controller.state.challenge!;

    final allowed = await app.webViews.navigate(
      redirectFor(challenge, ticket: 'ST-42'),
    );
    await tester.pump();

    expect(allowed, isFalse);
    expect(repo.completedTickets, ['ST-42']);
    expect(app.controller.state.phase, AuthPhase.wechatCompleting);
    expect(find.byKey(const Key('wechat.completing')), findsOneWidget);
    expect(find.text('正在确认登录…'), findsOneWidget);

    complete.complete(
      WechatResult(WechatStatus.success, session: testSession()),
    );
    await tester.pumpAndSettle();

    expect(app.controller.state.isAuthenticated, isTrue);
    expect(find.byType(WechatLoginPage), findsNothing);
    expect(homeShell, findsOneWidget);
    expect(find.textContaining(testToken), findsNothing);
  });

  testWidgets('success found by polling also closes the page', (tester) async {
    final repo = FakeAuthRepository();
    final app = await _openWechat(tester, repository: repo);
    await _loaded(tester, app);

    repo.onCheckWechat = () async =>
        WechatResult(WechatStatus.success, session: testSession());
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.byType(WechatLoginPage), findsNothing);
    expect(homeShell, findsOneWidget);
  });

  testWidgets('start failure shows a recoverable panel', (tester) async {
    var calls = 0;
    final repo = FakeAuthRepository()
      ..onStartWechat = () async {
        if (calls++ == 0) {
          throw const AuthFailure(AuthFailureKind.network, '网络连接失败，请重试');
        }
        return testChallenge();
      };
    final app = await _openWechat(tester, repository: repo);

    expect(find.text('扫码登录未完成'), findsOneWidget);
    expect(find.text('网络连接失败，请重试'), findsOneWidget);

    await tester.tap(find.byKey(const Key('wechat.retry')));
    await pumpTransitions(tester);
    await _loaded(tester, app);

    expect(repo.startWechatCalls, 2);
    expect(find.byKey(const Key('fake.webview')), findsOneWidget);
  });

  testWidgets('expired QR offers a fresh challenge with a new WebView', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    final app = await _openWechat(tester, repository: repo);
    await _loaded(tester, app);
    expect(app.webViews.created, 1);

    repo.onCheckWechat = () async => const WechatResult(WechatStatus.expired);
    await tester.pump(const Duration(seconds: 3));
    await pumpTransitions(tester);

    expect(find.text('二维码已过期'), findsOneWidget);
    expect(find.text('二维码已过期，请重新获取'), findsOneWidget);

    repo.onCheckWechat = null;
    await tester.tap(find.byKey(const Key('wechat.retry')));
    await pumpTransitions(tester);
    await _loaded(tester, app);
    expect(app.webViews.created, 2);
    expect(find.byKey(const Key('fake.webview')), findsOneWidget);
  });

  testWidgets('transient polling errors show a non-blocking notice', (
    tester,
  ) async {
    final repo = FakeAuthRepository()
      ..onCheckWechat = () async =>
          throw const AuthFailure(AuthFailureKind.network, '网络连接不稳定');
    final app = await _openWechat(tester, repository: repo);
    await _loaded(tester, app);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(find.textContaining('网络连接不稳定'), findsOneWidget);
    expect(find.byKey(const Key('fake.webview')), findsOneWidget);
    expect(app.controller.state.phase, AuthPhase.wechatPending);
  });

  testWidgets('main-frame load error can be reloaded', (tester) async {
    final app = await _openWechat(tester);
    await _loaded(tester, app);

    app.webViews.config!.onMainFrameError();
    await tester.pump();
    expect(find.byKey(const Key('wechat.loadFailed')), findsOneWidget);

    await tester.tap(find.text('重新加载'));
    await tester.pump();
    await _loaded(tester, app);
    expect(find.byKey(const Key('wechat.loadFailed')), findsNothing);
    expect(app.webViews.created, 2);
  });

  testWidgets('closing cancels the challenge so it cannot finish later', (
    tester,
  ) async {
    final repo = FakeAuthRepository();
    final app = await _openWechat(tester, repository: repo);
    await _loaded(tester, app);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    expect(find.byType(WechatLoginPage), findsNothing);
    expect(app.controller.state.phase, AuthPhase.signedOut);
    expect(app.controller.state.challenge, isNull);

    // Polling has stopped: a late "success" can no longer sign in.
    final polls = repo.checkWechatCalls;
    repo.onCheckWechat = () async =>
        WechatResult(WechatStatus.success, session: testSession());
    await tester.pump(const Duration(seconds: 5));
    expect(repo.checkWechatCalls, polls);
    expect(app.controller.state.isAuthenticated, isFalse);
  });

  testWidgets('"use password" returns to a clean login form', (tester) async {
    final repo = FakeAuthRepository()
      ..onCheckWechat = () async => const WechatResult(WechatStatus.expired);
    final app = await _openWechat(tester, repository: repo);
    await _loaded(tester, app);
    await tester.pump(const Duration(seconds: 3));
    await pumpTransitions(tester);
    expect(find.text('二维码已过期'), findsOneWidget);

    await tester.tap(find.text('改用账号密码登录'));
    await tester.pumpAndSettle();

    expect(loginForm, findsOneWidget);
    // The QR failure must not leak onto the password form.
    expect(find.text('二维码已过期，请重新获取'), findsNothing);
    expect(app.controller.state.failure, isNull);
  });

  testWidgets('fits a small phone at 2x text', (tester) async {
    useSmallScreen(tester, textScale: 2);
    final app = await _openWechat(tester);
    await _loaded(tester, app);

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('fake.webview'))).height,
      greaterThan(240),
    );
  });

  testWidgets('meets tap-target and labelling guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    final app = await _openWechat(tester);
    await _loaded(tester, app);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
