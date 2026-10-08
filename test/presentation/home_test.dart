import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/campus/campus.dart';
import 'package:xinli_lite/features/campus/presentation/coming_soon_page.dart';
import 'package:xinli_lite/features/campus/presentation/course_card.dart';
import 'package:xinli_lite/shared/theme/app_theme.dart';
import 'package:xinli_lite/shared/widgets/motion.dart';
import 'package:xinli_lite/shared/widgets/soft_backdrop.dart';

import '../support/campus_fakes.dart';
import '../support/fakes.dart';

Future<TestApp> _signedIn(WidgetTester tester, {UiCampusRepository? campus}) =>
    pumpTestApp(
      tester,
      repository: FakeAuthRepository(stored: testSession()),
      campusRepository: campus,
    );

/// "yyyy-MM-dd HH:mm-HH:mm" in campus time, [days] from today.
String _examTime(int days) {
  final t = campusNow(DateTime.now()).add(Duration(days: days));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} 09:00-11:00';
}

HomeSnapshot _snapshot({DaySchedule? day, ResourceState<Schedule>? schedule}) =>
    HomeSnapshot(
      profile: const ResourceState(),
      schedule:
          schedule ??
          ResourceState(phase: ResourcePhase.ready, data: testSchedule()),
      exams: const ResourceState(),
      now: DateTime.now(),
      day: day,
      upcomingExams: const [],
      undatedExams: const [],
    );

Future<void> _pumpCard(
  WidgetTester tester,
  HomeSnapshot snapshot, {
  VoidCallback? onRetry,
  VoidCallback? onOpenSchedule,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: CourseCard(
            snapshot: snapshot,
            onRetry: onRetry ?? () {},
            onOpenSchedule: onOpenSchedule ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

CourseOccurrence _occurrence(Duration startOffset, Duration length) {
  final start = DateTime.now().add(startOffset);
  return CourseOccurrence(
    course: testSchedule().courses.first,
    startsAt: start,
    endsAt: start.add(length),
  );
}

void main() {
  group('login → home hand-off', () {
    testWidgets('one shared backdrop, then a staggered entrance', (
      tester,
    ) async {
      final app = await pumpTestApp(tester);
      await tester.enterText(
        find.byKey(const Key('login.username')),
        '20230001',
      );
      await tester.enterText(find.byKey(const Key('login.password')), 'pw');
      await tester.tap(find.byKey(const Key('login.submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      // Mid hand-off: both screens exist, the background is never duplicated.
      expect(loginForm, findsOneWidget);
      expect(homeShell, findsOneWidget);
      expect(find.byType(SoftBackdrop), findsOneWidget);

      // Home sections start hidden and reveal in order.
      final reveals = find.descendant(
        of: homeShell,
        matching: find.byType(StaggeredReveal),
      );
      double opacityOf(int i) => tester
          .widget<FadeTransition>(
            find
                .descendant(
                  of: reveals.at(i),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;
      expect(opacityOf(0), lessThan(1));

      await tester.pump(const Duration(milliseconds: 250));
      expect(opacityOf(0), greaterThan(opacityOf(1)));

      await tester.pumpAndSettle();
      expect(loginForm, findsNothing);
      expect(app.controller.state.isAuthenticated, isTrue);
      expect(opacityOf(0), 1);
      expect(find.byType(SoftBackdrop), findsOneWidget);
      expect(greetingFor('张三'), findsOneWidget);
    });

    testWidgets('outgoing screen recedes fast; incoming is never gate-faded', (
      tester,
    ) async {
      await pumpTestApp(tester);
      await tester.enterText(
        find.byKey(const Key('login.username')),
        '20230001',
      );
      await tester.enterText(find.byKey(const Key('login.password')), 'pw');
      await tester.tap(find.byKey(const Key('login.submit')));
      await tester.pump();
      await tester.pump();

      // The gate wraps each screen in exactly one Opacity.
      double gateOpacity(Finder screen) => tester
          .widget<Opacity>(
            find.ancestor(of: screen, matching: find.byType(Opacity)).first,
          )
          .opacity;

      final samples = <(double login, double home)>[];
      for (var ms = 0; ms <= 240; ms += 30) {
        samples.add((gateOpacity(loginForm), gateOpacity(homeShell)));
        await tester.pump(const Duration(milliseconds: 30));
      }
      // Home is never dimmed by the gate; its own entrance does the reveal.
      expect(samples.every((s) => s.$2 == 1), isTrue);
      // Login accelerates out and is gone by ~210ms.
      expect(samples.first.$1, greaterThan(0.95));
      expect(samples[3].$1, greaterThan(samples[6].$1));
      expect(samples.last.$1, 0);
      await tester.pumpAndSettle();
    });

    testWidgets('reduce motion shows the home screen without delay', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final app = TestApp(FakeAuthRepository(stored: testSession()));
      await tester.pumpWidget(app.build());
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // The reveal's own fade (skeletons inside may still breathe).
      final reveals = find.byType(StaggeredReveal);
      expect(reveals, findsWidgets);
      for (var i = 0; i < reveals.evaluate().length; i++) {
        final fade = tester.widget<FadeTransition>(
          find
              .descendant(
                of: reveals.at(i),
                matching: find.byType(FadeTransition),
              )
              .first,
        );
        expect(fade.opacity.value, 1);
      }
      await tester.pumpAndSettle();
    });
  });

  group('course card', () {
    testWidgets('without a calendar it says so and links to the timetable', (
      tester,
    ) async {
      final app = await _signedIn(tester);
      expect(find.text('暂未配置校历'), findsOneWidget);
      expect(find.textContaining('已同步本学期 2 门课程'), findsOneWidget);
      expect(find.text('下一节'), findsNothing);
      expect(find.text('今日课程'), findsNothing);

      await tester.tap(find.text('查看课表'));
      await tester.pumpAndSettle();
      expect(find.textContaining('校历尚未配置'), findsOneWidget);
      await tester.tap(find.text('周视图'));
      await tester.pumpAndSettle();
      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('大学英语'), findsOneWidget);
      // Separate resources reuse the same fresh current-term snapshot.
      expect(app.campusRepository.scheduleCalls, 1);
    });

    testWidgets('in class: course, remaining time and progress', (
      tester,
    ) async {
      final current = _occurrence(
        const Duration(minutes: -30),
        const Duration(minutes: 90),
      );
      await _pumpCard(
        tester,
        _snapshot(
          day: DaySchedule(
            status: DayScheduleStatus.inClass,
            week: 6,
            courses: [current],
            current: current,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('正在上课'), findsOneWidget);
      expect(find.text('高等数学'), findsOneWidget);
      expect(find.textContaining('还剩'), findsOneWidget);
      expect(find.text('教3-201'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(1 / 3, 0.02));
    });

    testWidgets('upcoming: countdown to the next class', (tester) async {
      final next = _occurrence(
        const Duration(minutes: 35),
        const Duration(minutes: 90),
      );
      await _pumpCard(
        tester,
        _snapshot(
          day: DaySchedule(
            status: DayScheduleStatus.upcoming,
            week: 6,
            courses: [next],
            next: next,
          ),
        ),
      );
      expect(find.text('下一节'), findsOneWidget);
      expect(find.textContaining('还有 35 分钟'), findsOneWidget);
    });

    testWidgets('incomplete never claims a next class', (tester) async {
      final next = _occurrence(
        const Duration(minutes: 35),
        const Duration(minutes: 90),
      );
      await _pumpCard(
        tester,
        _snapshot(
          day: DaySchedule(
            status: DayScheduleStatus.incomplete,
            week: 6,
            courses: [next],
            next: next,
            unresolved: [testSchedule().courses.last],
          ),
        ),
      );
      expect(find.text('部分课程时间待确认'), findsOneWidget);
      expect(find.text('下一节'), findsNothing);
    });

    testWidgets('other day states have honest copy', (tester) async {
      final cases = {
        DayScheduleStatus.noClasses: '今天没有课',
        DayScheduleStatus.outsideTerm: '当前不在教学周',
        DayScheduleStatus.finished: '今天的课已全部结束',
      };
      for (final entry in cases.entries) {
        await _pumpCard(
          tester,
          _snapshot(day: DaySchedule(status: entry.key, week: 3)),
        );
        expect(find.text(entry.value), findsOneWidget);
      }
    });

    testWidgets('load failure offers retry', (tester) async {
      var retried = false;
      await _pumpCard(
        tester,
        _snapshot(
          schedule: const ResourceState(
            phase: ResourcePhase.failure,
            failure: CampusFailure(CampusFailureKind.network, '网络连接失败'),
          ),
        ),
        onRetry: () => retried = true,
      );
      expect(find.text('课表加载失败'), findsOneWidget);
      expect(find.text('网络连接失败'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retried, isTrue);
    });

    testWidgets('refresh failure keeps the card and notes the update time', (
      tester,
    ) async {
      final repo = UiCampusRepository();
      final app = await _signedIn(tester, campus: repo);
      repo.onSchedule = (_) async =>
          throw const CampusFailure(CampusFailureKind.network, '网络连接失败');
      unawaited(app.campus.home.load(refresh: true));
      await tester.pumpAndSettle();

      expect(find.text('暂未配置校历'), findsOneWidget);
      expect(find.textContaining('刷新失败'), findsOneWidget);
    });
  });

  group('entries', () {
    testWidgets('card balance counts up to the real value', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTestApp(
        tester,
        repository: FakeAuthRepository(stored: testSession()),
        settle: false,
      );
      // Mid count-up the digits are in flight, readers already get the value.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Merged into the tile's button label, e.g. "校园卡 ¥128.50".
      expect(find.bySemanticsLabel(RegExp(r'¥128\.50')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('¥128.50'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('electricity: set a room, then show the reading', (
      tester,
    ) async {
      final repo = UiCampusRepository();
      await _signedIn(tester, campus: repo);
      expect(find.text('设置宿舍'), findsOneWidget);

      await tester.tap(find.byKey(const Key('entry.electricity')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('room.submit')));
      await tester.pump();
      expect(find.text('请输入宿舍号'), findsOneWidget);

      await typeRoom(tester, '9#312');
      await tester.tap(find.byKey(const Key('room.submit')));
      await tester.pumpAndSettle();

      expect(repo.electricityRooms, ['9#312']);
      // The sheet now shows the reading; close it to see the home tile.
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('28.15 度'), findsOneWidget);
      expect(find.text('9#312'), findsOneWidget);
      expect(find.text('偏低'), findsNothing);
    });

    testWidgets('low electricity is flagged', (tester) async {
      final repo = UiCampusRepository()
        ..onElectricity = (_) async => testElectricity(value: '3.27');
      final app = await _signedIn(tester, campus: repo);
      unawaited(app.campus.loadElectricity('9#312'));
      await tester.pumpAndSettle();
      expect(find.text('3.27 度'), findsOneWidget);
      expect(find.text('偏低'), findsOneWidget);
    });

    testWidgets('graduation info opens an honest placeholder', (tester) async {
      await _signedIn(tester);
      await openTab(tester, '我的');
      await tester.tap(find.text('毕业情况'));
      await tester.pumpAndSettle();
      expect(find.byType(ComingSoonPage), findsOneWidget);
      expect(find.text('页面开发中'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ComingSoonPage), findsNothing);
    });
  });

  group('modules fail independently', () {
    testWidgets('exam failure only affects the exam tile', (tester) async {
      final repo = UiCampusRepository()
        ..onExams = () async =>
            throw const CampusFailure(CampusFailureKind.server, '考试安排暂时无法获取');
      await _signedIn(tester, campus: repo);

      expect(greetingFor('张三'), findsOneWidget);
      expect(find.text('暂未配置校历'), findsOneWidget);
      expect(find.text('¥128.50'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('entry.exams')),
          matching: find.text('暂不可用'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('slow modules show skeletons, not "empty"', (tester) async {
      final exams = Completer<List<Exam>>();
      final repo = UiCampusRepository()..onExams = () => exams.future;
      await pumpTestApp(
        tester,
        repository: FakeAuthRepository(stored: testSession()),
        campusRepository: repo,
        settle: false,
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('暂无安排'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('entry.exams')),
          matching: find.byType(Skeleton),
        ),
        findsOneWidget,
      );

      exams.complete(const []);
      await tester.pumpAndSettle();
      expect(find.text('暂无安排'), findsOneWidget);
    });
  });

  testWidgets('home no longer lists exams; the tile still counts them', (
    tester,
  ) async {
    final repo = UiCampusRepository()
      ..onExams = () async => [
        Exam(courseName: '数据结构', examTime: _examTime(3)),
        Exam(courseName: '线性代数', examTime: _examTime(1)),
      ];
    await _signedIn(tester, campus: repo);
    expect(find.text('近期考试'), findsNothing);
    expect(find.text('数据结构'), findsNothing);
    expect(find.text('2 场待考'), findsOneWidget);
  });

  testWidgets('hidden tabs are fully transparent and inert', (tester) async {
    await _signedIn(tester);
    double opacityAround(String key) => tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.byKey(Key(key)),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;

    await openTab(tester, '我的');
    expect(opacityAround('mine.scroll'), 1);
    expect(opacityAround('home.scroll'), 0);
    // The hidden home tab cannot receive taps.
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .ancestor(
                  of: find.byKey(const Key('home.scroll')),
                  matching: find.byType(IgnorePointer),
                )
                .first,
          )
          .ignoring,
      isTrue,
    );

    await openTab(tester, '首页');
    expect(opacityAround('home.scroll'), 1);
    expect(opacityAround('mine.scroll'), 0);
  });

  testWidgets('tab switch is a fade-through, never two pages at once', (
    tester,
  ) async {
    await _signedIn(tester);
    double opacityAround(String key) => tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.byKey(Key(key)),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;

    await openTab(tester, '课表');
    await openTab(tester, '首页');
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('home.nav')),
        matching: find.text('课表'),
      ),
    );
    await tester.pump();
    for (var ms = 0; ms <= 300; ms += 20) {
      final home = opacityAround('home.scroll');
      final schedule = opacityAround('schedule.scroll');
      // At most one page is ever more than faintly visible.
      expect(home > 0.5 && schedule > 0.5, isFalse, reason: 'at $ms ms');
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();
    expect(opacityAround('schedule.scroll'), 1);
    expect(opacityAround('home.scroll'), 0);
  });

  testWidgets('tabs keep state across switches', (tester) async {
    await _signedIn(tester);
    expect(find.byKey(const Key('home.avatar')), findsNothing);
    await openTab(tester, '我的');
    expect(find.text('学号 20230001'), findsOneWidget);

    await openTab(tester, '首页');
    expect(find.text('暂未配置校历'), findsOneWidget);
  });

  testWidgets('home meets tap-target and labelling guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await _signedIn(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
