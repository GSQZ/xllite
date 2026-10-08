import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/campus_fakes.dart';
import '../support/fakes.dart';

void main() {
  const channel = MethodChannel('xinli_lite/course_activities');
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return {'testing': call.method == 'startTest', 'phase': 'pending'};
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets(
    'Mine shows only the authorized account and starts/stops through the switch',
    (tester) async {
      tester.view.physicalSize = const Size(1206, 2622);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      if (const bool.fromEnvironment('CAPTURE_COURSE_UI')) {
        final bytes = File(
          '/System/Library/Fonts/STHeiti Light.ttc',
        ).readAsBytesSync();
        await (FontLoader(
          'Roboto',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
      final app = TestApp(
        FakeAuthRepository(stored: testSession(username: '202303310112')),
      );
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: app.build()),
      );
      await tester.pumpAndSettle();
      await openTab(tester, '我的');
      final toggle = find.byKey(const Key('mine.courseActivityTest'));
      final scroll = find
          .descendant(
            of: find.byKey(const Key('mine.scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(toggle, 120, scrollable: scroll);
      expect(toggle, findsOneWidget);
      if (const bool.fromEnvironment('CAPTURE_COURSE_UI')) {
        await tester.pumpAndSettle();
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '/tmp/xinli-course-mine.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      }
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.textContaining('正式课前自动提醒尚未启用'), findsOneWidget);
      await tester.tap(find.text('开始测试'));
      await tester.pumpAndSettle();
      expect(calls.where((m) => m == 'startTest'), hasLength(1));
      expect(tester.widget<Switch>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(calls, contains('stopTest'));
      expect(tester.widget<Switch>(toggle).value, isFalse);
      expect(tester.takeException(), isNull);
      await app.controller.signOut();
      await tester.pumpAndSettle();
      expect(toggle, findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'other accounts cannot see the test switch',
    (tester) async {
      await pumpTestApp(
        tester,
        repository: FakeAuthRepository(stored: testSession()),
      );
      await openTab(tester, '我的');
      expect(find.byKey(const Key('mine.courseActivityTest')), findsNothing);
      expect(calls, isNot(contains('startTest')));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
