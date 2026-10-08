import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/campus/campus.dart';
import 'package:xinli_lite/features/campus/presentation/campus_code_sheet.dart';
import 'package:xinli_lite/features/campus/presentation/card_page.dart';
import 'package:xinli_lite/features/campus/presentation/exams_page.dart';
import 'package:xinli_lite/features/campus/presentation/grades_page.dart';
import 'package:xinli_lite/features/campus/presentation/qr_view.dart';
import 'package:xinli_lite/shared/widgets/expand_route.dart';

import '../support/campus_fakes.dart';
import '../support/fakes.dart';

Future<TestApp> _signedIn(WidgetTester tester, {UiCampusRepository? campus}) =>
    pumpTestApp(
      tester,
      repository: FakeAuthRepository(stored: testSession()),
      campusRepository: campus,
    );

Future<void> _open(WidgetTester tester, String entryKey) async {
  await tester.tap(find.byKey(Key(entryKey)));
  await tester.pumpAndSettle();
}

Future<void> _closeSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('关闭'));
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byTooltip('返回').last);
  await tester.pumpAndSettle();
}

/// The page's own vertical scrollable (pills inside scroll horizontally).
Finder _scrollOf(String key) => find
    .descendant(of: find.byKey(Key(key)), matching: find.byType(Scrollable))
    .first;

String _examTime(int days, {int hour = 9}) {
  final t = campusNow(DateTime.now()).add(Duration(days: days));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(hour)}:00-${two(hour + 2)}:00';
}

/// The code page animates for as long as a code is valid, so it never
/// "settles"; step through frames instead.
Future<void> _frames(WidgetTester tester, [int count = 30]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

double _opacityAbove(WidgetTester tester, Finder finder) => tester
    .widget<Opacity>(
      find.ancestor(of: finder, matching: find.byType(Opacity)).first,
    )
    .opacity;

void main() {
  group('expand transition', () {
    testWidgets('the tapped tile grows into the page and shrinks back', (
      tester,
    ) async {
      await _signedIn(tester);
      final tile = tester.getRect(find.byKey(const Key('entry.grades')));
      final screen = tester.getRect(find.byType(MaterialApp));

      await tester.tap(find.byKey(const Key('entry.grades')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        find.byType(ExpandRoute<void>),
        findsNothing,
      ); // a route, not a widget
      final start = tester.getRect(find.byType(GradesPage));
      // Starts from the tile's footprint, not from the screen edge.
      expect(start.width, closeTo(tile.width, tile.width * 0.1));
      expect(start.center.dx, closeTo(tile.center.dx, 12));

      await tester.pump(const Duration(milliseconds: 220));
      final mid = tester.getRect(find.byType(GradesPage));
      expect(mid.width, greaterThan(tile.width * 1.2));
      expect(mid.width, lessThan(screen.width));
      // The source tile is hidden while its page is open.
      expect(_opacityAbove(tester, find.byKey(const Key('entry.grades'))), 0);

      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(GradesPage)), screen);

      await tester.tap(find.byTooltip('返回'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final closing = tester.getRect(find.byType(GradesPage));
      expect(closing.width, lessThan(screen.width));
      expect(closing.width, greaterThan(tile.width * 0.9));

      await tester.pumpAndSettle();
      expect(find.byType(GradesPage), findsNothing);
      expect(_opacityAbove(tester, find.byKey(const Key('entry.grades'))), 1);
    });

    testWidgets(
      'iOS edge swipe shrinks the page with the finger, then closes it',
      (tester) async {
        await _signedIn(tester);
        await _open(tester, 'entry.grades');
        final screen = tester.getRect(find.byType(MaterialApp));

        final gesture = await tester.startGesture(Offset(4, screen.height / 2));
        await gesture.moveBy(const Offset(20, 0));
        await gesture.moveBy(Offset(screen.width * 0.25, 0));
        await tester.pump();
        final dragged = tester.getRect(find.byType(GradesPage));
        expect(dragged.width, lessThan(screen.width));

        // Small drag released: springs back open.
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(GradesPage)), screen);

        // Long drag released: closes into the tile.
        final again = await tester.startGesture(Offset(4, screen.height / 2));
        await again.moveBy(const Offset(20, 0));
        await again.moveBy(Offset(screen.width * 0.6, 0));
        await tester.pump();
        await again.up();
        await tester.pumpAndSettle();
        expect(find.byType(GradesPage), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets('each entry opens its own page', (tester) async {
      await _signedIn(tester);
      await _open(tester, 'entry.exams');
      expect(find.byType(ExamsPage), findsOneWidget);
      await _back(tester);
      await _open(tester, 'entry.card');
      expect(find.byType(CardPage), findsOneWidget);
      await _back(tester);
      expect(find.byType(CardPage), findsNothing);
    });
  });

  group('grades', () {
    testWidgets('summary, term filter and text grades as written', (
      tester,
    ) async {
      await _signedIn(tester);
      await _open(tester, 'entry.grades');

      expect(find.text('3.12'), findsOneWidget);
      expect(find.text('9.5'), findsOneWidget); // credits, no trailing zeros
      expect(find.text('优秀'), findsOneWidget);
      expect(find.text('毕业审核'), findsOneWidget);
      expect(find.textContaining('来自毕业审核表'), findsOneWidget);
      expect(find.text('2025-2026 第2学期'), findsWidgets);

      // A term without a computable GPA shows a dash, never 0.
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('grades.terms')),
          matching: find.text('2025-2026 第1学期'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('—'), findsOneWidget);
      expect(find.text('暂无可计算绩点的课程'), findsOneWidget);
      expect(find.text('数据结构'), findsNothing);
      expect(find.text('高等数学'), findsWidgets);
      expect(find.text('未通过'), findsWidgets);
    });

    testWidgets('a row opens its details', (tester) async {
      await _signedIn(tester);
      await _open(tester, 'entry.grades');
      await tester.tap(find.text('数据结构'));
      await tester.pumpAndSettle();
      expect(find.text('课程编号'), findsOneWidget);
      expect(find.text('C1'), findsOneWidget);
      expect(find.text('教务成绩表'), findsOneWidget);
    });

    testWidgets('load failure offers a retry', (tester) async {
      var fail = true;
      final repo = UiCampusRepository()
        ..onGrades = () async {
          if (fail) {
            throw const CampusFailure(CampusFailureKind.network, '网络连接失败');
          }
          return testGrades();
        };
      await _signedIn(tester, campus: repo);
      await _open(tester, 'entry.grades');
      expect(find.text('成绩加载失败'), findsOneWidget);

      fail = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('3.12'), findsOneWidget);
    });
  });

  group('exams', () {
    testWidgets('next exam, upcoming, undated and folded past exams', (
      tester,
    ) async {
      final repo = UiCampusRepository()
        ..onExams = () async => [
          Exam(
            courseName: '计算机网络',
            examTime: _examTime(6),
            examPlace: '教4-305',
          ),
          Exam(
            courseName: '概率论',
            examTime: _examTime(3),
            examPlace: '教2-101',
            seatNo: '18',
          ),
          const Exam(courseName: '大学物理', examTime: '第18周'),
          Exam(courseName: '思想政治', examTime: _examTime(-5)),
        ];
      await _signedIn(tester, campus: repo);
      await _open(tester, 'entry.exams');

      expect(find.text('下一场 · 共 2 场待考'), findsOneWidget);
      expect(find.text('还有 3 天'), findsOneWidget);
      expect(find.text('概率论'), findsOneWidget);
      expect(find.text('计算机网络'), findsOneWidget);
      expect(find.text('第18周'), findsOneWidget);
      expect(find.text('思想政治'), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const Key('exams.past')),
        200,
        scrollable: _scrollOf('exams.scroll'),
      );
      await tester.tap(find.byKey(const Key('exams.past')));
      await tester.pumpAndSettle();
      expect(find.text('思想政治'), findsOneWidget);
    });

    testWidgets('no exams is an honest empty state', (tester) async {
      await _signedIn(tester);
      await _open(tester, 'entry.exams');
      expect(find.text('近期没有待考科目'), findsOneWidget);
      expect(find.text('暂无考试安排'), findsOneWidget);
    });

    test('countdown wording', () {
      final now = DateTime.utc(2026, 10, 8, 1); // 09:00 campus time
      ExamOccurrence at(Duration offset) => ExamOccurrence(
        const Exam(courseName: 'x'),
        now.add(offset),
        now.add(offset + const Duration(hours: 2)),
      );
      expect(examCountdown(at(const Duration(minutes: 40)), now), '还有 40 分钟');
      expect(
        examCountdown(at(const Duration(hours: -1)), now),
        startsWith('进行中'),
      );
      expect(examCountdown(at(const Duration(hours: 5)), now), '今天 14:00 开始');
      expect(examCountdown(at(const Duration(days: 1)), now), '明天 09:00 开始');
      expect(examCountdown(at(const Duration(days: 4)), now), '还有 4 天');
    });
  });

  group('campus card', () {
    testWidgets('balance, grouped transactions and paging', (tester) async {
      final repo = UiCampusRepository();
      await _signedIn(tester, campus: repo);
      await _open(tester, 'entry.card');

      expect(
        find.descendant(
          of: find.byKey(const Key('card.balance')),
          matching: find.text('¥128.50'),
        ),
        findsOneWidget,
      );
      expect(find.text('第1食堂窗口'), findsOneWidget);
      expect(find.text('-1.50'), findsOneWidget);
      expect(find.text('退款'), findsOneWidget);
      expect(find.text('10月8日 周四'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('没有更多记录了'),
        400,
        scrollable: _scrollOf('card.scroll'),
      );
      expect(repo.transactionCalls.map((c) => c.$2), [1, 2]);
      expect(find.text('第25食堂窗口'), findsOneWidget);
    });

    testWidgets('switching the range reloads with real dates', (tester) async {
      final repo = UiCampusRepository();
      await _signedIn(tester, campus: repo);
      await _open(tester, 'entry.card');

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('card.ranges')),
          matching: find.text('上月'),
        ),
      );
      await tester.pumpAndSettle();
      final query = repo.transactionCalls.last.$1;
      expect(repo.transactionCalls.last.$2, 1);
      expect(query.fromDate!.day, 1);
      expect(query.toDate!.isBefore(query.fromDate!), isFalse);
      expect(query.toDate!.add(const Duration(days: 1)).day, 1); // month end
    });

    testWidgets('a transaction opens its details', (tester) async {
      await _signedIn(tester);
      await _open(tester, 'entry.card');
      await tester.tap(find.text('第1食堂窗口'));
      await tester.pumpAndSettle();
      expect(find.text('流水号'), findsOneWidget);
      expect(find.text('J1'), findsOneWidget);
    });

    testWidgets('empty range is stated plainly', (tester) async {
      final repo = UiCampusRepository()
        ..onTransactions = (q, p) async => testTransactions(count: 0);
      await _signedIn(tester, campus: repo);
      await _open(tester, 'entry.card');
      expect(find.text('这段时间没有交易记录'), findsOneWidget);
    });
  });

  group('payment code', () {
    testWidgets('drops down from the top, not as a new page', (tester) async {
      await _signedIn(tester);
      await _open(tester, 'entry.card');
      await tester.tap(find.byKey(const Key('card.code')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final sheet = find.byType(CampusCodeSheet);
      // Entering from above the screen edge.
      expect(tester.getRect(sheet).top, lessThan(0));
      await _frames(tester, 12);
      expect(tester.getRect(sheet).top, closeTo(0, 1));
      // The card page stays underneath.
      expect(find.byType(CardPage), findsOneWidget);
      await _closeSheet(tester);
    });

    testWidgets('keeps one height through loading, ready and failure', (
      tester,
    ) async {
      final attempt = Completer<CampusCode>();
      final repo = UiCampusRepository()..onCampusCode = () => attempt.future;
      await _signedIn(tester, campus: repo);
      await _open(tester, 'entry.card');
      await tester.tap(find.byKey(const Key('card.code')));
      await _frames(tester, 12);

      double height() => tester.getSize(find.byType(CampusCodeSheet)).height;
      expect(find.text('正在获取付款码…'), findsOneWidget);
      final loading = height();

      attempt.complete(testCampusCode());
      await _frames(tester, 12);
      expect(find.text('张三 · 20230001'), findsOneWidget);
      expect(height(), loading);

      repo.onCampusCode = () async =>
          throw const CampusFailure(CampusFailureKind.server, '付款码暂时无法获取');
      await tester.tap(find.text('刷新'));
      await _frames(tester, 12);
      expect(find.text('付款码暂时无法获取'), findsOneWidget);
      expect(height(), loading);
      await _closeSheet(tester);
    });

    testWidgets('a balance drop while the code is shown reads as paid', (
      tester,
    ) async {
      var balance = '128.50';
      final repo = UiCampusRepository()
        ..onBalance = () async => [CardAccount(balance: balance, unit: '元')];
      final app = await _signedIn(tester, campus: repo);
      await _open(tester, 'entry.card');
      await tester.tap(find.byKey(const Key('card.code')));
      await _frames(tester, 12);
      expect(find.byKey(const Key('paid')), findsNothing);

      // Spent ¥1.50 — the newest transaction is the matching one.
      balance = '127.00';
      await tester.pump(const Duration(seconds: 3));
      await _frames(tester, 40);

      expect(find.text('支付成功'), findsOneWidget);
      expect(find.text('-¥1.50'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('paid')),
          matching: find.textContaining('第1食堂窗口'),
        ),
        findsOneWidget,
      );
      expect(find.text('已完成支付'), findsOneWidget);
      // The credential is dropped as soon as payment is seen.
      expect(app.campus.campusCode.usableCode, isNull);

      await tester.tap(find.byKey(const Key('paid.done')));
      await tester.pumpAndSettle();
      expect(find.byType(CampusCodeSheet), findsNothing);
    });

    testWidgets('a balance rise (refund, top-up) is not a payment', (
      tester,
    ) async {
      var balance = '128.50';
      final repo = UiCampusRepository()
        ..onBalance = () async => [CardAccount(balance: balance, unit: '元')];
      await _signedIn(tester, campus: repo);
      await _open(tester, 'entry.card');
      await tester.tap(find.byKey(const Key('card.code')));
      await _frames(tester, 12);

      balance = '150.00';
      await tester.pump(const Duration(seconds: 3));
      await _frames(tester, 20);
      expect(find.text('支付成功'), findsNothing);
      await _closeSheet(tester);
    });

    testWidgets('closes on a tap outside or an upward swipe', (tester) async {
      final app = await _signedIn(tester);
      await _open(tester, 'entry.card');

      await tester.tap(find.byKey(const Key('card.code')));
      await _frames(tester, 12);
      await tester.tapAt(
        Offset(20, tester.getSize(find.byType(MaterialApp)).height - 20),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CampusCodeSheet), findsNothing);
      expect(app.campus.campusCode.usableCode, isNull);

      await tester.tap(find.byKey(const Key('card.code')));
      await _frames(tester, 12);
      // A short swipe springs back.
      await tester.drag(
        find.byKey(const Key('topSheet.handle')),
        const Offset(0, -40),
      );
      await _frames(tester, 10);
      expect(find.byType(CampusCodeSheet), findsOneWidget);
      // A long one puts it away.
      await tester.fling(
        find.byKey(const Key('topSheet.handle')),
        const Offset(0, -300),
        1500,
      );
      await tester.pumpAndSettle();
      expect(find.byType(CampusCodeSheet), findsNothing);
    });

    testWidgets('exists only while its page is open', (tester) async {
      final repo = UiCampusRepository();
      final app = await _signedIn(tester, campus: repo);
      await _open(tester, 'entry.card');
      expect(repo.codeCalls, 0);

      await tester.tap(find.byKey(const Key('card.code')));
      await _frames(tester);
      expect(find.byType(CampusCodeSheet), findsOneWidget);
      expect(repo.codeCalls, 1);
      expect(find.byType(QrView), findsOneWidget);
      expect(find.text('张三 · 20230001'), findsOneWidget);
      expect(find.textContaining('秒后刷新'), findsOneWidget);
      expect(find.textContaining('余额 ¥128.50'), findsOneWidget);
      // The credential itself is never printed.
      expect(find.textContaining('PAY-CODE'), findsNothing);
      expect(app.campus.campusCode.usableCode, isNotNull);

      await _closeSheet(tester);
      expect(find.byType(CampusCodeSheet), findsNothing);
      expect(app.campus.campusCode.usableCode, isNull);
    });

    testWidgets('failure can be retried', (tester) async {
      var fail = true;
      final repo = UiCampusRepository()
        ..onCampusCode = () async {
          if (fail) {
            throw const CampusFailure(CampusFailureKind.server, '付款码暂时无法获取');
          }
          return testCampusCode();
        };
      await _signedIn(tester, campus: repo);
      await _open(tester, 'entry.card');
      await tester.tap(find.byKey(const Key('card.code')));
      await _frames(tester);
      expect(find.text('付款码暂时无法获取'), findsOneWidget);

      fail = false;
      await tester.tap(find.byKey(const Key('code.retry')));
      await _frames(tester);
      expect(find.byType(QrView), findsOneWidget);
      await _closeSheet(tester);
    });

    testWidgets('an expired code is replaced automatically', (tester) async {
      var n = 0;
      final repo = UiCampusRepository()
        ..onCampusCode = () async =>
            testCampusCode(value: 'C${++n}', seconds: 5);
      await _signedIn(tester, campus: repo);
      await _open(tester, 'entry.card');
      await tester.tap(find.byKey(const Key('card.code')));
      await _frames(tester);
      expect(repo.codeCalls, 1);

      await tester.pump(const Duration(seconds: 6));
      await _frames(tester);
      expect(repo.codeCalls, 2);
      expect(find.byType(QrView), findsOneWidget);
      await _closeSheet(tester);
    });
  });

  testWidgets('feature pages fit a small phone at 2x text', (tester) async {
    useSmallScreen(tester, textScale: 2);
    await _signedIn(tester);
    for (final key in ['entry.grades', 'entry.exams', 'entry.card']) {
      await tester.scrollUntilVisible(
        find.byKey(Key(key)),
        120,
        scrollable: _scrollOf('home.scroll'),
      );
      await tester.pumpAndSettle();
      await _open(tester, key);
      expect(tester.takeException(), isNull, reason: key);
      await _back(tester);
    }
  });

  testWidgets('pages meet tap-target and labelling guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _signedIn(tester);
    for (final key in ['entry.grades', 'entry.exams', 'entry.card']) {
      await _open(tester, key);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await _back(tester);
    }
    handle.dispose();
  });

  testWidgets('pages are emptied on sign-out without flashing', (tester) async {
    final app = await _signedIn(tester);
    await _open(tester, 'entry.grades');
    unawaited(app.controller.signOut());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Still showing the last real content while it animates away.
    if (find.byType(GradesPage).evaluate().isNotEmpty) {
      expect(find.text('数据结构'), findsWidgets);
    }
    await tester.pumpAndSettle();
    expect(find.byType(GradesPage), findsNothing);
    expect(loginForm, findsOneWidget);
  });
}
