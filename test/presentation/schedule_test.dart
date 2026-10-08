import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/campus/campus.dart';
import 'package:xinli_lite/features/campus/presentation/campus_format.dart';

import '../support/campus_fakes.dart';
import '../support/fakes.dart';
import '../features/campus/schedule_school_format_test.dart'
    show spanningSchedule, practiceSchedule;

Future<TestApp> _schedule(WidgetTester tester, {Schedule? schedule}) async {
  final repo = UiCampusRepository()
    ..onSchedule = (_) async => schedule ?? testCalendarSchedule();
  final app = await pumpTestApp(
    tester,
    repository: FakeAuthRepository(stored: testSession()),
    campusRepository: repo,
  );
  await openTab(tester, '课表');
  return app;
}

int get _today => campusNow(DateTime.now()).weekday;

/// The visible view; the week grid also lists today's course.
/// Text inside the day view (the week grid, behind it, repeats courses).
Finder inDay(String text) => find.descendant(
  of: find.byKey(const Key('schedule.dayList')),
  matching: find.text(text),
);

Finder inWeek(String text) => find.descendant(
  of: find.byKey(const Key('schedule.grid')),
  matching: find.text(text),
);

void expectPainted(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final opacities = tester.widgetList<Opacity>(
    find.ancestor(of: finder, matching: find.byType(Opacity)),
  );
  expect(
    opacities.every((o) => o.opacity > 0),
    isTrue,
    reason: 'Content in the widget tree must actually be visible',
  );
  expect(finder.hitTestable(), findsOneWidget);
}

Finder block(String title) => find.ancestor(
  of: inWeek(title),
  matching: find.byWidgetPredicate(
    (w) => w.key is ValueKey && w.key.toString().contains('schedule.block'),
  ),
);

Schedule denseSchedule() {
  final calendar = testCalendar();
  return Schedule(
    term: calendar.term,
    calendar: AcademicCalendar(
      term: calendar.term,
      firstMonday: calendar.firstMonday,
      weekCount: calendar.weekCount,
      sections: const [
        SectionTime(1, 600, 645),
        SectionTime(2, 655, 700),
        SectionTime(3, 720, 765),
        SectionTime(4, 775, 820),
        SectionTime(5, 960, 1005),
        SectionTime(6, 1015, 1060),
        SectionTime(7, 1080, 1125),
        SectionTime(8, 1135, 1180),
        SectionTime(9, 1230, 1275),
        SectionTime(10, 1285, 1330),
      ],
    ),
    courses: [
      for (final (title, day, sections) in [
        ('软件工程与项目管理', '星期一', '1-2'),
        ('并行课程', '星期一', '1-2'),
        ('下午独立课程', '星期一', '5-6'),
        ('单节课程', '星期三', '3'),
        ('周日晚课', '星期日', '9-10'),
      ])
        ScheduleCourse(
          title: title,
          day: day,
          sections: sections,
          weeks: '1-16',
          location: '教3-201',
          teacher: '测试教师',
        ),
    ],
  );
}

void main() {
  _compactLocationCases();

  testWidgets(
    'busy and empty days keep the same viewport height throughout transitions',
    (tester) async {
      await _schedule(tester, schedule: denseSchedule());
      await tester.tap(find.byKey(const Key('schedule.day.1')));
      await tester.pumpAndSettle();
      final viewport = find.byKey(const Key('schedule.dayViewport'));
      final height = tester.getSize(viewport).height;
      expect(height, greaterThanOrEqualTo(320));
      for (final day in [2, 3, 4, 1]) {
        await tester.tap(find.byKey(Key('schedule.day.$day')));
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 40));
          for (final element in tester.elementList(viewport)) {
            expect((element.renderObject as RenderBox).size.height, height);
          }
        }
        await tester.pumpAndSettle();
        expect(tester.getSize(viewport).height, height);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty and busy weeks keep identical grid height', (
    tester,
  ) async {
    await _schedule(tester, schedule: denseSchedule());
    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();
    final height = tester
        .getSize(find.byKey(const Key('schedule.weekScroll')))
        .height;
    for (var i = 6; i < 17; i++) {
      await tester.tap(find.byKey(const Key('schedule.nextWeek')));
      await tester.pumpAndSettle();
    }
    expect(
      tester.getSize(find.byKey(const Key('schedule.weekScroll'))).height,
      height,
    );
  });

  testWidgets(
    'week seventeen practice occupies five rows on each of two days',
    (tester) async {
      final original = practiceSchedule();
      await _schedule(
        tester,
        schedule: Schedule(
          term: original.term,
          courses: original.courses,
          calendar: AcademicCalendar(
            term: original.term,
            firstMonday: testCalendar().firstMonday,
            weekCount: 19,
            sections: original.calendar!.sections,
          ),
        ),
      );
      for (var i = 6; i < 17; i++) {
        await tester.tap(find.byKey(const Key('schedule.nextWeek')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('周视图'));
      await tester.pumpAndSettle();
      expect(find.text('第 17 周'), findsOneWidget);
      expect(inWeek('实践课程'), findsNWidgets(10));
      final rectangles = tester
          .elementList(block('实践课程'))
          .map(
            (e) => tester.getRect(
              find.byElementPredicate((other) => identical(other, e)),
            ),
          )
          .toList();
      expect(rectangles.map((r) => r.left).toSet(), hasLength(2));
      expect(rectangles.map((r) => r.top).toSet(), hasLength(5));
      for (var i = 0; i < rectangles.length; i++) {
        expect(rectangles[i].height, greaterThan(90));
        for (var j = i + 1; j < rectangles.length; j++) {
          expect(rectangles[i].overlaps(rectangles[j]), isFalse);
        }
      }
      expect(find.textContaining('时间无法确定'), findsNothing);
      await tester.tap(find.text('当日'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('schedule.day.3')));
      await tester.pumpAndSettle();
      expect(inDay('实践课程'), findsNWidgets(5));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('week seven spanning class is visible once in both views', (
    tester,
  ) async {
    final original = spanningSchedule();
    final schedule = Schedule(
      term: original.term,
      courses: original.courses,
      calendar: AcademicCalendar(
        term: original.term,
        firstMonday: testCalendar().firstMonday,
        weekCount: 19,
        sections: original.calendar!.sections,
      ),
    );
    await _schedule(tester, schedule: schedule);
    await tester.tap(find.byKey(const Key('schedule.nextWeek')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();
    expect(find.text('第 7 周'), findsOneWidget);
    expect(inWeek('跨四节课程'), findsOneWidget);
    expect(find.textContaining('时间无法确定'), findsNothing);
    expect(tester.getRect(block('跨四节课程')).height, greaterThan(190));
    await tester.tap(find.text('当日'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('schedule.day.3')));
    await tester.pumpAndSettle();
    expectPainted(tester, inDay('跨四节课程'));
    expect(inDay('18:00'), findsOneWidget);
    expect(inDay('22:10'), findsOneWidget);
    expect(find.text('时间待定'), findsNothing);
  });

  testWidgets(
    'mode switch keeps header and controls fixed throughout animation',
    (tester) async {
      useSmallScreen(tester);
      await _schedule(tester);
      final toggle = find.byKey(const Key('schedule.mode'));
      final previousWeek = find.byKey(const Key('schedule.prevWeek'));
      final beforeToggle = tester.getRect(toggle);
      final beforeWeek = tester.getRect(previousWeek);
      for (final label in ['周视图', '当日', '周视图', '当日']) {
        await tester.tap(find.text(label));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 40));
          expect(tester.getRect(toggle), beforeToggle);
          expect(tester.getRect(previousWeek), beforeWeek);
        }
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'five weekdays fit and scrolling viewport reaches both screen edges',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402, 874);
      addTearDown(tester.view.reset);
      final calendar = testCalendar();
      await _schedule(
        tester,
        schedule: Schedule(
          term: calendar.term,
          calendar: calendar,
          courses: const [
            ScheduleCourse(
              title: '软件需求工程与建模',
              day: '星期一',
              sections: '5-6',
              weeks: '1-16',
              location: '【10号实验楼】软件开发实验室【10#414】',
            ),
            ScheduleCourse(
              title: '计算机网络',
              day: '星期五',
              sections: '1-2',
              weeks: '1-16',
              location: '【工科实训楼】网络实验室【工科实训楼403室】',
            ),
          ],
        ),
      );
      await tester.tap(find.text('周视图'));
      await tester.pumpAndSettle();
      final viewport = tester.getRect(
        find.byKey(const Key('schedule.weekScroll')),
      );
      expect(viewport.left, 0);
      expect(viewport.right, 402);
      final scroll = find.descendant(
        of: find.byKey(const Key('schedule.weekScroll')),
        matching: find.byType(Scrollable),
      );
      expect(tester.state<ScrollableState>(scroll).position.maxScrollExtent, 0);
      expectPainted(tester, inWeek('实训403'));
      expectPainted(tester, inWeek('10#414'));
      expect(tester.getRect(block('计算机网络')).right, lessThan(402));
      expect(
        tester
            .renderObject<RenderParagraph>(inWeek('软件需求工程与建模'))
            .didExceedMaxLines,
        isFalse,
      );
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('long room stays separate from title at text scale $scale', (
      tester,
    ) async {
      useSmallScreen(tester, textScale: scale);
      final calendar = testCalendar();
      await _schedule(
        tester,
        schedule: Schedule(
          term: calendar.term,
          calendar: calendar,
          courses: const [
            ScheduleCourse(
              title: '计算机网络课程设计',
              day: '星期一',
              sections: '1',
              weeks: '1-16',
              location: '计算机网络工程实验室A305',
            ),
          ],
        ),
      );
      await tester.tap(find.text('周视图'));
      await tester.pumpAndSettle();
      final title = inWeek('计算机网络课程设计');
      final room = inWeek('计算机网络工程实验室A305');
      final titleRect = tester.getRect(title);
      final roomRect = tester.getRect(room);
      final tileRect = tester.getRect(block('计算机网络课程设计'));
      expect(roomRect.top - titleRect.bottom, greaterThanOrEqualTo(4.9));
      expect(roomRect.bottom, lessThanOrEqualTo(tileRect.bottom - 4.9));
      expect(roomRect.left, greaterThanOrEqualTo(tileRect.left + 3.9));
      expect(roomRect.right, lessThanOrEqualTo(tileRect.right - 3.9));
      expect(tester.widget<Text>(room).style?.fontSize, 10.5);
      expect(
        find.ancestor(of: room, matching: find.byType(FittedBox)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('当日 opens on today with real class times', (tester) async {
    await _schedule(tester);
    expect(find.text('第 6 周'), findsOneWidget);
    expect(find.text('本周'), findsOneWidget);
    expect(inDay('线性代数'), findsOneWidget);
    expect(inDay('14:00'), findsOneWidget);
    expect(inDay('15:40'), findsOneWidget);
    expect(find.textContaining('今天'), findsWidgets);
  });

  testWidgets('picking another day in the strip shows its classes', (
    tester,
  ) async {
    await _schedule(tester);
    final monday = _today == 1 ? 3 : 1;
    await tester.tap(find.byKey(Key('schedule.day.$monday')));
    await tester.pumpAndSettle();
    expect(inDay(monday == 1 ? '高等数学' : '大学英语'), findsOneWidget);
    expect(find.text(monday == 1 ? '08:00' : '10:00'), findsOneWidget);
    expect(inDay('线性代数'), findsNothing);
    expectPainted(tester, inDay(monday == 1 ? '高等数学' : '大学英语'));
  });

  testWidgets('周视图 places each course in its weekday column', (tester) async {
    await _schedule(tester);
    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();

    final monday = tester.getCenter(find.text('周一'));
    final wednesday = tester.getCenter(find.text('周三'));
    expect(
      (tester.getCenter(inWeek('高等数学')).dx - monday.dx).abs(),
      lessThan(60),
    );
    expect(
      (tester.getCenter(inWeek('大学英语')).dx - wednesday.dx).abs(),
      lessThan(60),
    );
    // 1-2 sits above 3-4.
    expect(
      tester.getTopLeft(inWeek('高等数学')).dy,
      lessThan(tester.getTopLeft(inWeek('大学英语')).dy),
    );
  });

  testWidgets('week arrows move through teaching weeks', (tester) async {
    await _schedule(tester);
    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();

    expect(inWeek('线性代数'), findsOneWidget);

    await tester.tap(find.byKey(const Key('schedule.nextWeek')));
    await tester.pumpAndSettle();
    expect(find.text('第 7 周'), findsOneWidget);
    expect(find.text('回到本周'), findsOneWidget);
    // Only runs in weeks 1-6.
    expect(inDay('线性代数'), findsNothing);
    expect(find.text('高等数学'), findsOneWidget);

    await tester.tap(find.text('回到本周'));
    await tester.pumpAndSettle();
    expect(find.text('第 6 周'), findsOneWidget);
    expect(inWeek('线性代数'), findsOneWidget);
  });

  testWidgets('a holiday from the calendar cancels the day', (tester) async {
    final now = campusNow(DateTime.now());
    final calendar = testCalendar(
      overrides: [
        CalendarDateOverride(
          date: DateTime.utc(now.year, now.month, now.day),
          scheduleDate: null,
          reason: '国庆节',
        ),
      ],
    );
    await _schedule(tester, schedule: testCalendarSchedule(calendar: calendar));
    expect(find.text('国庆节 · 停课'), findsOneWidget);
    expect(find.text('今日停课'), findsOneWidget);
    expect(inDay('线性代数'), findsNothing);
  });

  testWidgets('the week grid gives the room its own readable area', (
    tester,
  ) async {
    await _schedule(tester);
    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();

    final room = find.descendant(
      of: find.byKey(const Key('schedule.grid')),
      matching: find.text('3-201'),
    );
    expect(room, findsOneWidget);
    expect(tester.widget<Text>(room).style?.fontSize, 10.5);
    expect(tester.widget<Text>(room).softWrap, isTrue);
    expect(tester.widget<Text>(room).maxLines, 1);
    expect(
      find.ancestor(of: room, matching: find.byType(FittedBox)),
      findsNothing,
    );
    expect(
      tester.getTopLeft(room).dy - tester.getBottomLeft(inWeek('高等数学')).dy,
      greaterThanOrEqualTo(5),
    );
    // The full label is still available in the detail sheet.
    await tester.tap(room);
    await tester.pumpAndSettle();
    expect(find.text('教3-201'), findsOneWidget);
  });

  testWidgets('switching days never shows two day views at once', (
    tester,
  ) async {
    await _schedule(tester);
    final other = _today == 1 ? 2 : 1;

    await tester.tap(find.byKey(Key('schedule.day.$other')));
    await tester.pump();

    for (var ms = 0; ms <= 500; ms += 20) {
      final layers = tester
          .widgetList<Opacity>(
            find.descendant(
              of: find.byKey(const Key('schedule.scroll')),
              matching: find.byType(Opacity),
            ),
          )
          .map((o) => o.opacity)
          .where((o) => o > 0.06 && o < 0.99)
          .length;
      // At most one view is mid-fade: the other is fully in or fully out.
      expect(layers, lessThan(2), reason: 'at $ms ms');
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(inDay(_today == 1 ? '大学英语' : '高等数学'), findsOneWidget);
  });

  testWidgets('a course opens its details', (tester) async {
    await _schedule(tester);
    await tester.tap(inDay('线性代数'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.descendant(of: find.byType(BottomSheet), matching: find.text('赵老师')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('第5-6节'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('switching views keeps one control and fits a small phone', (
    tester,
  ) async {
    useSmallScreen(tester, textScale: 2);
    await _schedule(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching back to day paints classes and accepts taps', (
    tester,
  ) async {
    await _schedule(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('周视图'));
      await tester.pumpAndSettle();
      expectPainted(tester, inWeek('高等数学'));
      await tester.tap(find.text('当日'));
      await tester.pumpAndSettle();
      expectPainted(tester, inDay('线性代数'));
    }
    await tester.tap(inDay('线性代数'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('rapid day changes finish visible, and empty days are visible', (
    tester,
  ) async {
    await _schedule(tester, schedule: denseSchedule());
    for (final day in [1, 3, 7, 1]) {
      await tester.tap(find.byKey(Key('schedule.day.$day')));
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pumpAndSettle();
    expectPainted(tester, inDay('软件工程与项目管理'));
    await tester.tap(find.byKey(const Key('schedule.day.2')));
    await tester.pumpAndSettle();
    expectPainted(tester, inDay('这天没有课'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('week grid separates rows and reserves readable conflict lanes', (
    tester,
  ) async {
    useSmallScreen(tester);
    await _schedule(tester, schedule: denseSchedule());
    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();
    final morning = tester.getRect(block('软件工程与项目管理'));
    final conflict = tester.getRect(block('并行课程'));
    final afternoon = tester.getRect(block('下午独立课程'));
    expect(morning.width, greaterThanOrEqualTo(40));
    expect(morning.height, greaterThan(90));
    expect(morning.overlaps(conflict), isFalse);
    expect(afternoon.top, greaterThan(morning.bottom));
    expect(afternoon.width, greaterThan(morning.width * 1.9));
    expect(tester.getRect(block('周日晚课')).top, greaterThan(afternoon.bottom));
    expect(find.text('左右滑动查看完整课表'), findsOneWidget);
    final horizontal = find.descendant(
      of: find.byKey(const Key('schedule.weekScroll')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(horizontal).position;
    final viewport = tester.getRect(
      find.byKey(const Key('schedule.weekScroll')),
    );
    expect(viewport.left, 0);
    expect(viewport.right, 320);
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.dragFrom(
      tester.getTopLeft(find.byKey(const Key('schedule.weekScroll'))) +
          const Offset(230, 85),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(find.text('第 6 周'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'week tiles wrap long titles and keep single sections within bounds',
    (tester) async {
      useSmallScreen(tester, textScale: 2);
      await _schedule(tester, schedule: denseSchedule());
      await tester.tap(find.text('周视图'));
      await tester.pumpAndSettle();
      final title = tester.renderObject<RenderParagraph>(inWeek('软件工程与项目管理'));
      expect(title.size.height, greaterThan(30));
      expect(tester.getRect(block('单节课程')).height, greaterThan(90));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('day swipe advances to the next day and remains visible', (
    tester,
  ) async {
    await _schedule(tester, schedule: denseSchedule());
    await tester.tap(find.byKey(const Key('schedule.day.1')));
    await tester.pumpAndSettle();
    await tester.fling(inDay('软件工程与项目管理'), const Offset(-200, 0), 800);
    await tester.pumpAndSettle();
    expectPainted(tester, inDay('这天没有课'));
  });

  testWidgets('calendar-free timetable stays visible in both views', (
    tester,
  ) async {
    await _schedule(tester, schedule: testSchedule());
    await tester.tap(find.byKey(const Key('schedule.day.1')));
    await tester.pumpAndSettle();
    expectPainted(tester, inDay('高等数学'));
    expect(find.textContaining('未按教学周筛选'), findsOneWidget);
    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();
    expectPainted(tester, inWeek('高等数学'));
    expect(
      tester.getRect(block('大学英语')).top,
      greaterThan(tester.getRect(block('高等数学')).top),
    );
  });

  testWidgets('reduced motion switches directly to visible content', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await _schedule(tester);
    await tester.tap(find.text('周视图'));
    await tester.pumpAndSettle();
    expectPainted(tester, inWeek('高等数学'));
    await tester.tap(find.text('当日'));
    await tester.pumpAndSettle();
    expectPainted(tester, inDay('线性代数'));
  });
}

void _compactLocationCases() {
  test('room labels are shortened without losing the number', () {
    expect(compactLocation('教3-201'), '3-201');
    expect(compactLocation('教学楼A305'), 'A305');
    expect(compactLocation('3-201教室'), '3-201');
    expect(compactLocation(' 9#312 '), '9#312');
    expect(compactLocation('教材室'), '教材室');
    expect(compactLocation('体育馆-羽毛球馆-3号场'), '体育馆');
    expect(compactLocation(''), '');
    expect(compactLocation('【10号实验楼】 软件开发实验室 【10#414】'), '10#414');
    expect(compactLocation('【1号教学楼】 JT1204'), 'JT1204');
    expect(compactLocation('【工科实训楼】 动画技术实验室 【工科实训楼403室】'), '实训403');
  });
}
