import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/auth/auth.dart';

import 'support/campus_fakes.dart';
import 'support/fakes.dart';

void main() {
  testWidgets('shows restoring screen, then login when nothing is saved', (
    tester,
  ) async {
    final read = Completer<AuthSession?>();
    final repo = FakeAuthRepository()..onRead = () => read.future;
    await pumpTestApp(tester, repository: repo, settle: false);
    await tester.pump();

    expect(find.text('正在恢复登录状态…'), findsOneWidget);
    expect(loginForm, findsNothing);

    read.complete(null);
    await tester.pumpAndSettle();
    expect(loginForm, findsOneWidget);
    expect(find.text('正在恢复登录状态…'), findsNothing);
  });

  testWidgets('restores a saved session without showing the token', (
    tester,
  ) async {
    await pumpTestApp(
      tester,
      repository: FakeAuthRepository(stored: testSession()),
    );

    expect(homeShell, findsOneWidget);
    expect(greetingFor('张三'), findsOneWidget);
    expect(find.textContaining(testToken), findsNothing);
  });

  testWidgets('我的 shows the student id from the profile', (tester) async {
    await pumpTestApp(
      tester,
      repository: FakeAuthRepository(stored: testSession(username: '')),
    );
    await openTab(tester, '我的');
    expect(find.text('学号 20230001'), findsOneWidget);
    expect(find.text('软件工程'), findsOneWidget);
  });

  testWidgets('password sign-in, then sign-out returns to login', (
    tester,
  ) async {
    final app = await pumpTestApp(tester);

    await tester.enterText(find.byKey(const Key('login.username')), '20230001');
    await tester.enterText(find.byKey(const Key('login.password')), 'pw');
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pumpAndSettle();

    expect(app.controller.state.isAuthenticated, isTrue);
    expect(homeShell, findsOneWidget);

    await signOutFromMine(tester);

    expect(app.controller.state.phase, AuthPhase.signedOut);
    expect(app.repository.stored, isNull);
    expect(loginForm, findsOneWidget);
  });

  testWidgets('sign-out shows progress and blocks repeat taps', (tester) async {
    final clearing = Completer<void>();
    final repo = FakeAuthRepository(stored: testSession())
      ..onClear = () => clearing.future;
    await pumpTestApp(tester, repository: repo);

    await signOutFromMine(tester, settle: false);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('正在退出…'), findsOneWidget);
    // Profile stays on screen although the business layer already cleared it.
    expect(find.text('学号 20230001'), findsOneWidget);
    expect(find.text('软件工程'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.descendant(
        of: find.byKey(const Key('mine.signOut')),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(button.onPressed, isNull);

    clearing.complete();
    await tester.pumpAndSettle();
    expect(repo.clearCalls, 1);
    expect(loginForm, findsOneWidget);
  });

  testWidgets('failed sign-out keeps an error and a retry entry', (
    tester,
  ) async {
    final repo = FakeAuthRepository(stored: testSession())..clearFailures = 1;
    final app = await pumpTestApp(tester, repository: repo);

    await signOutFromMine(tester);

    expect(find.text('退出未完成'), findsOneWidget);
    expect(find.textContaining('无法清除本机登录信息'), findsOneWidget);
    expect(repo.stored, isNotNull);

    // Typing in the form must not hide the retry prompt.
    await tester.enterText(find.byKey(const Key('login.username')), '2023');
    await tester.pump();
    expect(find.text('重试退出'), findsOneWidget);

    await tester.tap(find.text('重试退出'));
    await tester.pumpAndSettle();

    expect(repo.clearCalls, 2);
    expect(repo.stored, isNull);
    expect(find.text('退出未完成'), findsNothing);
    expect(app.controller.state.failure, isNull);
  });

  testWidgets('restore failure offers a retry on the login screen', (
    tester,
  ) async {
    var attempts = 0;
    final repo = FakeAuthRepository()
      ..onRead = () async {
        if (attempts++ == 0) {
          throw const AuthFailure(AuthFailureKind.storage, '读取本机登录信息失败');
        }
        return null;
      };
    await pumpTestApp(tester, repository: repo);

    expect(find.text('未能恢复登录'), findsOneWidget);
    expect(find.text('读取本机登录信息失败'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(repo.readCalls, 2);
    expect(find.text('未能恢复登录'), findsNothing);
    expect(loginForm, findsOneWidget);
  });

  testWidgets('network failure on refresh keeps a still-valid session', (
    tester,
  ) async {
    final repo =
        FakeAuthRepository(
            stored: testSession(lifetime: const Duration(minutes: 1)),
          )
          ..onRefresh = (_) async =>
              throw const AuthFailure(AuthFailureKind.network, '网络连接失败');
    final app = await pumpTestApp(tester, repository: repo);

    expect(app.controller.state.isAuthenticated, isTrue);
    expect(homeShell, findsOneWidget);
    expect(find.text('登录状态暂未刷新'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭提示'));
    await tester.pumpAndSettle();
    expect(find.text('登录状态暂未刷新'), findsNothing);
    expect(app.controller.state.isAuthenticated, isTrue);
  });

  testWidgets('returning to the foreground asks the controller to refresh', (
    tester,
  ) async {
    final repo =
        FakeAuthRepository(
            stored: testSession(lifetime: const Duration(seconds: 90)),
          )
          ..onRefresh = (_) async =>
              testSession(lifetime: const Duration(seconds: 90));
    await pumpTestApp(tester, repository: repo);
    expect(repo.refreshCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(repo.refreshCalls, 2);
  });

  testWidgets('home and 我的 fit a small phone at 2x text', (tester) async {
    useSmallScreen(tester, textScale: 2);
    await pumpTestApp(
      tester,
      repository: FakeAuthRepository(stored: testSession()),
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const Key('entry.electricity')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('home.scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(tester.takeException(), isNull);

    await openTab(tester, '我的');
    await tester.scrollUntilVisible(
      find.byKey(const Key('mine.signOut')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('mine.scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
