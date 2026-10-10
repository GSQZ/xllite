import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/campus_fakes.dart';
import '../support/fakes.dart';

void main() {
  const channel = MethodChannel('xinli_lite/course_activities');
  bool enabled = false;
  bool island = false;
  bool denied = false;
  final methods = <String>[];
  setUp(() {
    enabled = island = denied = false;
    methods.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          methods.add(call.method);
          if (call.method == 'configure') {
            final args = call.arguments as Map;
            enabled = args['enabled'] == true;
            island = args['liveActivities'] == true;
          }
          return {
            'enabled': enabled,
            'liveActivities': island,
            'scheduledSupported': true,
            'activitiesAllowed': true,
            'notificationPermission': denied ? 'denied' : 'authorized',
            'warning': denied ? '通知未获允许，请在系统设置中开启课前通知' : null,
          };
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<TestApp> open(WidgetTester tester) async {
    final app = TestApp(FakeAuthRepository(stored: testSession()));
    await tester.pumpWidget(app.build());
    await tester.pumpAndSettle();
    app.campus.home.configureCalendar(testCalendar());
    await openTab(tester, '我的');
    final link = find.byKey(const Key('mine.courseReminders'));
    final scroll = find
        .descendant(
          of: find.byKey(const Key('mine.scroll')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(link, 100, scrollable: scroll);
    await tester.pumpAndSettle();
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets(
    'ordinary account enables reminders and explicitly accepts island limits',
    (tester) async {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await open(tester);
      final reminders = find.byKey(const Key('reminders.enabled'));
      final sheet = find.byKey(const Key('reminders.sheetHeight'));
      final closedHeight = tester.getSize(sheet).height;
      expect(tester.widget<SwitchListTile>(reminders).value, isFalse);
      await tester.tap(reminders);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final expandingHeight = tester.getSize(sheet).height;
      await tester.pumpAndSettle();
      final openHeight = tester.getSize(sheet).height;
      expect(expandingHeight, greaterThan(closedHeight));
      expect(expandingHeight, lessThan(openHeight));
      expect(tester.widget<SwitchListTile>(reminders).value, isTrue);
      expect(methods, contains('sync'));
      await tester.tap(reminders);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final collapsingHeight = tester.getSize(sheet).height;
      expect(collapsingHeight, greaterThan(closedHeight));
      expect(collapsingHeight, lessThan(openHeight));
      await tester.pumpAndSettle();
      expect(tester.getSize(sheet).height, closeTo(closedHeight, 0.1));
      await tester.tap(reminders);
      await tester.pumpAndSettle();
      expect(find.textContaining('每次打开 App 会核对'), findsNothing);
      expect(find.textContaining('安排更新于'), findsNothing);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      await tester.pumpAndSettle();
      final live = find.byKey(const Key('reminders.island'));
      await tester.tap(live);
      await tester.pumpAndSettle();
      expect(find.text('开启灵动岛？'), findsOneWidget);
      expect(find.textContaining('可能继续保留'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(island, isFalse);
      await tester.tap(live);
      await tester.pumpAndSettle();
      await tester.tap(find.text('开启'));
      await tester.pumpAndSettle();
      expect(island, isTrue);
      await tester.tap(find.byKey(const Key('reminders.details')));
      await tester.pumpAndSettle();
      expect(find.textContaining('开课 1 分钟后收起'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'denied permissions remain actionable on small screen with large text',
    (tester) async {
      useSmallScreen(tester, textScale: 2);
      denied = true;
      await open(tester);
      final reminders = find.byKey(const Key('reminders.enabled'));
      await tester.ensureVisible(reminders);
      await tester.tap(reminders);
      await tester.pumpAndSettle();
      final settings = find.byKey(const Key('reminders.settings'));
      await tester.ensureVisible(settings);
      await tester.pumpAndSettle();
      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(methods, contains('openSettings'));
      expect(find.text('通知未开启'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Android profile does not show an unsupported island setting',
    (tester) async {
      await pumpTestApp(
        tester,
        repository: FakeAuthRepository(stored: testSession()),
      );
      await openTab(tester, '我的');
      expect(find.byKey(const Key('mine.courseReminders')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'old preview account also has only the production entry',
    (tester) async {
      await pumpTestApp(
        tester,
        repository: FakeAuthRepository(
          stored: testSession(username: '202303310112'),
        ),
      );
      await openTab(tester, '我的');
      expect(find.byKey(const Key('mine.courseReminders')), findsOneWidget);
      expect(find.text('灵动岛测试'), findsNothing);
      expect(methods, isNot(contains('startTest')));
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
