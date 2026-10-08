import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/campus/campus.dart';
import 'package:xinli_lite/features/campus/presentation/electricity_sheet.dart';
import 'package:xinli_lite/features/campus/presentation/pay_brand_icon.dart';
import 'package:xinli_lite/features/campus/presentation/room_keypad.dart';
import 'package:xinli_lite/features/campus/presentation/payment_webview_page.dart';
import 'package:xinli_lite/shared/theme/app_theme.dart';

import '../support/campus_fakes.dart';
import '../support/fakes.dart';

Future<TestApp> _signedIn(WidgetTester tester, {UiCampusRepository? campus}) =>
    pumpTestApp(
      tester,
      repository: FakeAuthRepository(stored: testSession()),
      campusRepository: campus,
    );

Future<void> _openElectricity(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('entry.electricity')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('without a room the electricity sheet asks for one', (
    tester,
  ) async {
    final repo = UiCampusRepository();
    await _signedIn(tester, campus: repo);
    await _openElectricity(tester);
    expect(find.byType(ElectricitySheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ElectricitySheet),
        matching: find.text('设置宿舍'),
      ),
      findsOneWidget,
    );

    await typeRoom(tester, '9#312');
    await tester.tap(find.byKey(const Key('room.submit')));
    await tester.pumpAndSettle();
    expect(repo.electricityRooms, ['9#312']);
    expect(find.text('28.15 度'), findsWidgets);
  });

  testWidgets('with a room it is a sheet, not a page', (tester) async {
    final app = await _signedIn(tester);
    unawaited(app.campus.loadElectricity('9#312'));
    await tester.pumpAndSettle();
    await _openElectricity(tester);

    final sheet = find.byType(ElectricitySheet);
    expect(sheet, findsOneWidget);
    // Drops from the top and leaves the home screen visible below.
    expect(tester.getRect(sheet).top, lessThan(80));
    expect(
      tester.getRect(sheet).height,
      lessThan(tester.getSize(find.byType(MaterialApp)).height),
    );
    expect(find.text('9号宿舍楼 · 312房间'), findsOneWidget);
    expect(find.byKey(const Key('electricity.recharge')), findsOneWidget);
    expect(find.textContaining('本地记录'), findsNothing);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(ElectricitySheet), findsNothing);
  });

  testWidgets('low electricity is called out', (tester) async {
    final repo = UiCampusRepository()
      ..onElectricity = (_) async => testElectricity(value: '3.27');
    final app = await _signedIn(tester, campus: repo);
    unawaited(app.campus.loadElectricity('9#312'));
    await tester.pumpAndSettle();
    await _openElectricity(tester);
    expect(find.text('电量偏低，建议尽快充值'), findsOneWidget);
  });

  testWidgets('changing the room happens inside the sheet', (tester) async {
    final repo = UiCampusRepository();
    final app = await _signedIn(tester, campus: repo);
    unawaited(app.campus.loadElectricity('9#312'));
    await tester.pumpAndSettle();
    await _openElectricity(tester);

    await tester.tap(find.byKey(const Key('electricity.room')));
    await tester.pumpAndSettle();
    expect(find.text('更换宿舍'), findsOneWidget);
    await typeRoom(tester, '5#524');
    await tester.tap(find.byKey(const Key('room.submit')));
    await tester.pumpAndSettle();
    expect(repo.electricityRooms.last, '5#524');
    expect(find.byType(ElectricitySheet), findsOneWidget);
  });

  testWidgets('room entry uses the drawn keypad, never the system keyboard', (
    tester,
  ) async {
    await _signedIn(tester);
    await _openElectricity(tester);
    expect(find.byType(EditableText), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);

    // "#" cannot lead, and only one is allowed.
    await tester.tap(find.byKey(const Key('room.key.#')));
    await tester.tap(find.byKey(const Key('room.key.9')));
    await tester.tap(find.byKey(const Key('room.key.#')));
    await tester.tap(find.byKey(const Key('room.key.#')));
    await tester.tap(find.byKey(const Key('room.key.3')));
    await tester.pump();
    expect(find.text('9#3'), findsOneWidget);

    // Incomplete format is explained, not sent.
    await tester.longPress(find.byKey(const Key('room.key.back')));
    await tester.tap(find.byKey(const Key('room.key.9')));
    await tester.tap(find.byKey(const Key('room.submit')));
    await tester.pump();
    expect(find.textContaining('楼号#房间号'), findsOneWidget);
  });

  test('saved rooms are normalised for the keypad', () {
    expect(keypadRoom('5号楼524'), '5#524');
    expect(keypadRoom(' 9#312 '), '9#312');
    expect(keypadRoom(null), '');
  });

  testWidgets('card page offers 付款码 and 充值 side by side', (tester) async {
    await _signedIn(tester);
    await tester.tap(find.byKey(const Key('entry.card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('card.code')), findsOneWidget);
    expect(find.byKey(const Key('card.recharge')), findsOneWidget);
    expect(find.textContaining('本地记录'), findsNothing);
    expect(find.textContaining('正在更新'), findsNothing);
  });

  testWidgets('我的 no longer offers cache clearing', (tester) async {
    await _signedIn(tester);
    await openTab(tester, '我的');
    expect(find.text('清理缓存'), findsNothing);
  });

  test('pay methods map to their brands', () {
    PayMethod m(String code, String name) => PayMethod(code: code, name: name);
    expect(payBrandOf(m('01', '支付宝')), PayBrand.alipay);
    expect(payBrandOf(m('02', '微信')), PayBrand.wechat);
    expect(payBrandOf(m('06', '余额支付')), PayBrand.card);
    expect(payBrandOf(m('09', '银行卡')), PayBrand.other);
  });

  testWidgets('brand icons render at any size', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Row(
          children: [
            PayBrandIcon(brand: PayBrand.wechat),
            PayBrandIcon(brand: PayBrand.alipay, size: 22),
            PayBrandIcon(brand: PayBrand.card),
          ],
        ),
      ),
    );
    expect(find.text('支'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('checkout without a usable link explains and offers 返回核对', (
    tester,
  ) async {
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PaymentWebViewPage(
                        result: PaymentResult.fromJson({
                          'type': 'wechat_jsapi',
                        }),
                      ),
                    ),
                  );
                  popped = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payment.error')), findsOneWidget);
    await tester.tap(find.byKey(const Key('payment.back')));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
  });

  testWidgets('electricity sheet fits a small phone at 2x text', (
    tester,
  ) async {
    useSmallScreen(tester, textScale: 2);
    final repo = UiCampusRepository()
      ..onElectricity = (_) async => testElectricity(value: '3.27');
    final app = await _signedIn(tester, campus: repo);
    unawaited(app.campus.loadElectricity('9#312'));
    await tester.pumpAndSettle();
    final tile = find.byKey(const Key('entry.electricity'));
    await tester.scrollUntilVisible(
      tile,
      120,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('home.scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(ElectricitySheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
