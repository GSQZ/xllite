import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/campus/campus.dart';
import 'package:xinli_lite/features/campus/presentation/payment_webview_page.dart';
import 'package:xinli_lite/features/campus/presentation/recharge_sheet.dart';
import 'package:xinli_lite/shared/theme/app_theme.dart';
import 'package:xinli_lite/shared/widgets/drawn_keypad.dart';

import '../features/campus/support.dart';
import '../support/fakes.dart';

/// Own-card balance that a test can raise to simulate money arriving.
class _BalanceRepo extends FakeCampusRepository {
  _BalanceRepo([this.value = '118.00']);

  String value;

  @override
  Future<List<CardAccount>> balance() async => [CardAccount(balance: value)];
}

/// Goes through checkout for a ¥[amount] own-card top-up and comes back.
Future<void> payAndReturn(WidgetTester tester, String amount) async {
  await typeAmount(tester, amount);
  await next(tester);
  await tester.tap(find.byKey(const Key('recharge.confirm')));
  await tester.pumpAndSettle();
  await tester.pageBack();
  await frames(tester, 10);
}

/// Opens the recharge sheet from a host page.
Future<(CampusController, FakeCampusRepository)> showRecharge(
  WidgetTester tester, {
  bool electric = true,
  FakeCampusRepository? repository,
}) async {
  final auth = AuthController(repository: FakeAuthRepository());
  final repo = repository ?? FakeCampusRepository();
  final campus = CampusController(auth: auth, repository: repo);
  addTearDown(() {
    campus.dispose();
    auth.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showRechargeSheet(
                context,
                campus: campus,
                room: electric ? '9#312' : null,
                paymentBuilder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('测试收银台')),
                  body: const Text('等待外部支付'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (campus, repo);
}

Finder get _sheetScroll => find
    .descendant(
      of: find.byKey(const Key('recharge.scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 100, scrollable: _sheetScroll);
  await tester.pumpAndSettle();
}

/// Opens a drawn field's keypad and types [text] on it.
Future<void> typeInto(
  WidgetTester tester,
  String field,
  String pad,
  String text,
) async {
  await reveal(tester, find.byKey(Key('recharge.$field')));
  await tester.tap(find.byKey(Key('recharge.$field')));
  await tester.pumpAndSettle();
  for (final ch in text.split('')) {
    final key = find.byKey(Key('$pad.key.$ch'));
    await reveal(tester, key);
    await tester.tap(key);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> typeAmount(WidgetTester tester, String text) =>
    typeInto(tester, 'amount', 'amount', text);

/// "下一步" on the form.
Future<void> next(WidgetTester tester) async {
  final button = find.byKey(const Key('recharge.submit'));
  await reveal(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> frames(WidgetTester tester, [int n = 15]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  test(
    'payment links permit only payment schemes and forms do not double-submit',
    () {
      expect(
        paymentExternalUri(Uri.parse('weixin://pay/test'))?.scheme,
        'weixin',
      );
      expect(
        paymentExternalUri(
          Uri.parse('intent://pay/test#Intent;scheme=alipays;end'),
        )?.scheme,
        'alipays',
      );
      expect(
        paymentExternalUri(Uri.parse('intent://evil#Intent;scheme=file;end')),
        isNull,
      );
      expect(paymentExternalUri(Uri.parse('file:///etc/passwd')), isNull);
      expect(
        paymentFormDocument(
          '<form></form>',
        ).contains('document.forms[0].submit()'),
        isTrue,
      );
      final scripted = paymentFormDocument(
        '<form></form><script>document.forms[0].submit();</script>',
      );
      expect('document.forms[0].submit()'.allMatches(scripted).length, 1);
    },
  );

  testWidgets(
    'electricity requires a password and explicit confirmation; duplicate taps send one charge',
    (tester) async {
      final pending = Completer<PaymentOrder>();
      final repo = FakeCampusRepository()..onPay = () => pending.future;
      final (campus, _) = await showRecharge(tester, repository: repo);

      await typeAmount(tester, '30');
      await next(tester);
      expect(find.text('请输入一卡通支付密码'), findsOneWidget);
      expect(repo.charges, 0);

      await typeInto(tester, 'password', 'password', '123456');
      await next(tester);
      // Confirmation step inside the same sheet; nothing charged yet.
      expect(find.text('确认电费充值'), findsOneWidget);
      expect(find.text('¥30.00'), findsOneWidget);
      expect(repo.charges, 0);

      await tester.tap(find.byKey(const Key('recharge.confirm')));
      await frames(tester, 4); // the button spins while in flight
      expect(repo.charges, 1);
      expect(campus.payments.state.phase, PaymentPhase.submitting);
      expect(find.text('正在提交…'), findsOneWidget);
      await tester.tap(find.byKey(const Key('recharge.confirm')));
      await tester.pump();
      expect(repo.charges, 1);

      pending.complete(
        PaymentOrder.fromJson(example('newcard.electricity.recharge.pay')),
      );
      await tester.pumpAndSettle();
      expect(find.text('电费充值成功'), findsOneWidget);
      expect(repo.charges, 1);
    },
  );

  testWidgets(
    'card order opens checkout but returning never reports payment success',
    (tester) async {
      final (campus, repo) = await showRecharge(tester, electric: false);
      await typeAmount(tester, '50');
      await next(tester);
      expect(repo.orders, 0);
      await tester.tap(find.byKey(const Key('recharge.confirm')));
      await tester.pumpAndSettle();
      expect(find.text('测试收银台'), findsOneWidget);
      expect(repo.orders, 1);

      await tester.pageBack();
      await frames(tester, 20);
      expect(find.text('等待到账'), findsOneWidget);
      expect(find.text('电费充值成功'), findsNothing);
      expect(find.text('充值已到账'), findsNothing);
      expect(campus.payments.state.phase, PaymentPhase.awaitingExternalPayment);
      expect(repo.orders, 1);

      await tester.tap(find.byKey(const Key('recharge.close')));
      await tester.pumpAndSettle();
      expect(find.byType(RechargeFlow), findsNothing);
    },
  );

  testWidgets('own-card money arriving after checkout is shown as arrived', (
    tester,
  ) async {
    final repo = _BalanceRepo();
    final (campus, _) = await showRecharge(
      tester,
      electric: false,
      repository: repo,
    );
    await typeAmount(tester, '50');
    await next(tester);
    await tester.tap(find.byKey(const Key('recharge.confirm')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await frames(tester, 10);
    expect(find.text('等待到账'), findsOneWidget);

    // The school config said ¥118.00; ¥50 later arrives.
    repo.value = '168.00';
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('充值已到账'), findsOneWidget);
    expect(find.text('+¥50.00'), findsOneWidget);
    // Acknowledged, so a new top-up is allowed.
    expect(campus.payments.state.canSubmit, isTrue);
    await tester.tap(find.byKey(const Key('paid.done')));
    await tester.pumpAndSettle();
  });

  testWidgets('下一步 shows the confirm step fully, not a blank sheet', (
    tester,
  ) async {
    await showRecharge(tester, electric: false);
    await typeAmount(tester, '50');
    await next(tester);
    final confirm = find.byKey(const Key('recharge.confirm'));
    expect(confirm, findsOneWidget);
    var visible = 1.0;
    for (final o in tester.widgetList<Opacity>(
      find.ancestor(of: confirm, matching: find.byType(Opacity)),
    )) {
      visible *= o.opacity;
    }
    expect(visible, 1);
    // And back again.
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    final submit = find.byKey(const Key('recharge.submit'));
    visible = 1.0;
    for (final o in tester.widgetList<Opacity>(
      find.ancestor(of: submit, matching: find.byType(Opacity)),
    )) {
      visible *= o.opacity;
    }
    expect(visible, 1);
  });

  testWidgets(
    'arrival uses the polled balance, not the recharge config (16 → 17)',
    (tester) async {
      // The config says ¥118.00, the balance query says ¥16.00: the
      // "before" figure must come from the balance query.
      final repo = _BalanceRepo('16.00');
      await showRecharge(tester, electric: false, repository: repo);
      await payAndReturn(tester, '1');
      expect(find.text('等待到账'), findsOneWidget);
      expect(find.text('当前余额 ¥16.00'), findsOneWidget);

      repo.value = '17.00';
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('充值已到账'), findsOneWidget);
      expect(find.text('+¥1.00'), findsOneWidget);
      expect(find.text('正在查看到账…'), findsNothing);
      await tester.tap(find.byKey(const Key('paid.done')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('a new matching transaction also counts as arrived', (
    tester,
  ) async {
    final repo = _BalanceRepo('16.00');
    var paid = false;
    repo.onTransactions = (q, page) async => TransactionPage.fromJson({
      'fromDate': '2026-10-01',
      'toDate': '2026-10-09',
      'tradeType': '1,2,3',
      'pageNo': page,
      'pageSize': 20,
      'transactions': [
        if (paid)
          {
            'date': '2026-10-09 12:00:00',
            'summary': '充值',
            'merchantName': '',
            'amount': '+20.00',
            'isRefund': '否',
            'journo': 'NEW-1',
          },
        {
          'date': '2026-10-08 12:00:00',
          'summary': '消费',
          'merchantName': '食堂',
          'amount': '-8.00',
          'isRefund': '否',
          'journo': 'OLD-1',
        },
      ],
    });
    await showRecharge(tester, electric: false, repository: repo);
    await payAndReturn(tester, '20');
    expect(find.text('等待到账'), findsOneWidget);

    // Balance query lags, the transaction list already has it.
    paid = true;
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('充值已到账'), findsOneWidget);
    await tester.tap(find.byKey(const Key('paid.done')));
    await tester.pumpAndSettle();
  });

  testWidgets('已到账 settles it by hand and unlocks new top-ups', (tester) async {
    final (campus, _) = await showRecharge(tester, electric: false);
    await payAndReturn(tester, '50');
    expect(find.byKey(const Key('recharge.arrived')), findsOneWidget);
    await tester.tap(find.byKey(const Key('recharge.arrived')));
    await tester.pumpAndSettle();
    expect(find.text('充值完成'), findsOneWidget);
    expect(campus.payments.state.canSubmit, isTrue);
    await tester.tap(find.byKey(const Key('paid.done')));
    await tester.pumpAndSettle();
  });

  testWidgets('no input in the sheet opens the system keyboard', (
    tester,
  ) async {
    await showRecharge(tester);
    expect(find.byType(EditableText), findsNothing);
    await typeAmount(tester, '12.5');
    expect(find.text('12.5'), findsOneWidget);
    await typeInto(tester, 'password', 'password', '1234');
    // Masked: four dots in the six cells, digits never shown.
    expect(find.text('1234'), findsNothing);
    for (var i = 0; i < 6; i++) {
      expect(
        find.byKey(ValueKey('pin.filled.$i')),
        i < 4 ? findsOneWidget : findsNothing,
      );
    }
    expect(find.byType(EditableText), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);

    // Fewer than six digits is explained, not sent.
    await next(tester);
    expect(find.text('请输入 6 位支付密码'), findsOneWidget);

    // The sixth digit completes the PIN and puts the keypad away.
    await typeInto(tester, 'password', 'password', '56');
    expect(find.byKey(const ValueKey('pin.filled.5')), findsOneWidget);
    expect(find.byKey(const Key('password.key.1')), findsNothing);
  });

  test('amount keypad rules', () {
    expect(appendAmount('', '.'), '0.');
    expect(appendAmount('0', '5'), '5');
    expect(appendAmount('12.3', '4'), '12.34');
    expect(appendAmount('12.34', '5'), isNull);
    expect(appendAmount('12.3', '.'), isNull);
    expect(appendAmount('99999', '9'), isNull);
    expect(appendDigit('123', '4', max: 3), isNull);
  });

  testWidgets('an unacknowledged top-up locks the form until confirmed', (
    tester,
  ) async {
    final (campus, _) = await showRecharge(tester, electric: false);
    await typeAmount(tester, '50');
    await next(tester);
    await tester.tap(find.byKey(const Key('recharge.confirm')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await frames(tester, 10);
    await tester.tap(find.byKey(const Key('recharge.close')));
    await tester.pumpAndSettle();

    // Reopen: the previous order must be acknowledged first.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recharge.pending')), findsOneWidget);
    await tester.tap(find.byKey(const Key('recharge.acknowledge')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recharge.pending')), findsNothing);
    expect(campus.payments.state.canSubmit, isTrue);
  });

  testWidgets('recharge sheet fits small phone with keyboard and large text', (
    tester,
  ) async {
    useSmallScreen(tester, textScale: 2, keyboardHeight: 220);
    await showRecharge(tester);
    await reveal(tester, find.byKey(const Key('recharge.password')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('other-student confirmation uses the last edited recipient', (
    tester,
  ) async {
    final (_, repo) = await showRecharge(tester, electric: false);
    await typeAmount(tester, '50');
    await reveal(tester, find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await typeInto(tester, 'other', 'other', '20239999');
    await next(tester);
    expect(find.text('学号 20239999'), findsOneWidget);
    expect(repo.orders, 0);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(repo.orders, 0);
    expect(find.byKey(const Key('recharge.submit')), findsOneWidget);
  });
}
