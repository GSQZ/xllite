import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/auth/auth.dart';

import '../support/campus_fakes.dart';
import '../support/fakes.dart';

Finder _field(String key) => find.byKey(Key(key));

EditableText _editable(WidgetTester tester, String key) =>
    tester.widget<EditableText>(
      find.descendant(of: _field(key), matching: find.byType(EditableText)),
    );

TextField _textField(WidgetTester tester, String key) =>
    tester.widget<TextField>(
      find.descendant(of: _field(key), matching: find.byType(TextField)),
    );

ButtonStyleButton _button(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );

void main() {
  testWidgets('shows the form, autofill hints and disclaimer', (tester) async {
    await pumpTestApp(tester);

    expect(find.text('学号'), findsOneWidget);
    expect(find.text('CAS 密码'), findsOneWidget);
    expect(find.text('微信扫码登录'), findsOneWidget);
    expect(find.textContaining('民间开发版本，不代表学校官方应用'), findsOneWidget);
    expect(find.textContaining('客户端仅保存登录令牌'), findsOneWidget);
    expect(find.textContaining('仅在本机'), findsNothing);

    final username = _editable(tester, 'login.username');
    expect(username.autofillHints, [AutofillHints.username]);
    expect(username.textInputAction, TextInputAction.next);
    final password = _editable(tester, 'login.password');
    expect(password.autofillHints, [AutofillHints.password]);
    expect(password.textInputAction, TextInputAction.done);
    expect(password.obscureText, isTrue);
    expect(password.autocorrect, isFalse);
  });

  testWidgets('password visibility toggles with a labelled button', (
    tester,
  ) async {
    await pumpTestApp(tester);
    await tester.enterText(_field('login.password'), 'secret');

    expect(find.byTooltip('显示密码'), findsOneWidget);
    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump();
    expect(_editable(tester, 'login.password').obscureText, isFalse);
    expect(find.byTooltip('隐藏密码'), findsOneWidget);

    await tester.tap(find.byTooltip('隐藏密码'));
    await tester.pump();
    expect(_editable(tester, 'login.password').obscureText, isTrue);
  });

  testWidgets('empty submit shows field errors without a request', (
    tester,
  ) async {
    final app = await pumpTestApp(tester);

    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pumpAndSettle();

    expect(find.text('请输入学号'), findsOneWidget);
    expect(find.text('请输入 CAS 密码'), findsOneWidget);
    expect(app.repository.signInCalls, isEmpty);

    // A whitespace-only password is still a password; only empty is rejected.
    await tester.enterText(_field('login.username'), '20230001');
    await tester.enterText(_field('login.password'), '   ');
    await tester.pump();
    expect(find.text('请输入学号'), findsNothing);
    expect(find.text('请输入 CAS 密码'), findsNothing);
  });

  testWidgets('keyboard next moves focus and done submits untrimmed password', (
    tester,
  ) async {
    final app = await pumpTestApp(tester);

    await tester.showKeyboard(_field('login.username'));
    tester.testTextInput.enterText(' 20230001 ');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(_editable(tester, 'login.password').focusNode.hasFocus, isTrue);

    tester.testTextInput.enterText(' p@ss word ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(app.repository.signInCalls, hasLength(1));
    expect(app.repository.signInCalls.single.username, '20230001');
    expect(app.repository.signInCalls.single.password, ' p@ss word ');
    expect(app.controller.state.isAuthenticated, isTrue);
  });

  testWidgets('request in flight locks the form; failure allows retry', (
    tester,
  ) async {
    var attempt = Completer<AuthSession>();
    final repo = FakeAuthRepository()..onSignIn = (_) => attempt.future;
    final app = await pumpTestApp(tester, repository: repo);

    await tester.enterText(_field('login.username'), '20230001');
    await tester.enterText(_field('login.password'), 'wrong');
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pump();

    // Form stays on screen; the button reports progress and is inert.
    expect(find.text('正在登录…'), findsOneWidget);
    expect(loginForm, findsOneWidget);
    expect(_button(tester, 'login.submit').onPressed, isNull);
    expect(_button(tester, 'login.wechat').onPressed, isNull);
    expect(_textField(tester, 'login.username').enabled, isFalse);
    expect(_textField(tester, 'login.password').enabled, isFalse);
    await tester.tap(
      find.byKey(const Key('login.submit')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(repo.signInCalls, hasLength(1));

    attempt.completeError(
      const AuthFailure(AuthFailureKind.rejected, '学号或密码错误'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login.error')), findsOneWidget);
    expect(find.text('学号或密码错误'), findsOneWidget);
    expect(_button(tester, 'login.submit').onPressed, isNotNull);
    expect(_textField(tester, 'login.password').enabled, isTrue);
    // Entered values are kept so the user can correct them.
    expect(find.text('20230001'), findsOneWidget);

    attempt = Completer<AuthSession>();
    await tester.tap(find.byKey(const Key('login.submit')));
    await pumpTransitions(tester); // let the old banner fade out
    expect(repo.signInCalls, hasLength(2));
    expect(find.text('学号或密码错误'), findsNothing);

    attempt.complete(testSession());
    await tester.pumpAndSettle();
    expect(app.controller.state.isAuthenticated, isTrue);
    expect(homeShell, findsOneWidget);
  });

  testWidgets('editing a field clears a stale error', (tester) async {
    final repo = FakeAuthRepository()
      ..onSignIn = (_) async =>
          throw const AuthFailure(AuthFailureKind.network, '网络连接失败，请重试');
    await pumpTestApp(tester, repository: repo);

    await tester.enterText(_field('login.username'), '20230001');
    await tester.enterText(_field('login.password'), 'pw');
    await tester.tap(find.byKey(const Key('login.submit')));
    await tester.pumpAndSettle();
    expect(find.text('网络连接失败，请重试'), findsOneWidget);

    await tester.enterText(_field('login.password'), 'pw2');
    await tester.pumpAndSettle();
    expect(find.text('网络连接失败，请重试'), findsNothing);
  });

  testWidgets('small phone with keyboard and 2x text stays usable', (
    tester,
  ) async {
    useSmallScreen(tester, textScale: 2, keyboardHeight: 260);
    final repo = FakeAuthRepository()
      ..onSignIn = (_) async => throw const AuthFailure(
        AuthFailureKind.rejected,
        '学号或密码错误，多次失败可能触发学校认证系统的安全限制',
      );
    await pumpTestApp(tester, repository: repo);
    expect(tester.takeException(), isNull);

    await tester.enterText(_field('login.username'), '20230001');
    await tester.enterText(_field('login.password'), 'pw');
    final submit = find.byKey(const Key('login.submit'));
    await tester.scrollUntilVisible(submit, 80, scrollable: pageScrollable);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(repo.signInCalls, hasLength(1));
    await tester.scrollUntilVisible(
      find.byKey(const Key('login.error')),
      -80,
      scrollable: pageScrollable,
    );
    expect(find.byKey(const Key('login.error')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('民间开发版本'),
      80,
      scrollable: pageScrollable,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide screens keep the form at a readable width', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 768);
    addTearDown(tester.view.reset);
    await pumpTestApp(tester);

    expect(tester.getSize(_field('login.username')).width, lessThan(441));
  });

  testWidgets('meets tap-target and labelling guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpTestApp(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
