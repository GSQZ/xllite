import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/campus/campus.dart';
import 'package:xinli_lite/shared/theme/theme_settings.dart';

import '../support/campus_fakes.dart';
import '../support/fakes.dart';

/// A timetable pinned to today's campus weekday, so the tests never depend
/// on which day of the week they happen to run: 高等数学 in 第1-2节
/// (08:00–09:40) and 线性代数 in 第5-6节 (14:00–15:40).
Schedule _todaySchedule() {
  final weekday = campusNow(DateTime.now()).weekday;
  const names = ['一', '二', '三', '四', '五', '六', '日'];
  return Schedule(
    term: '2026-2027-1',
    calendar: testCalendar(),
    calendarStatus: 'confirmed',
    termLabel: '2026–2027学年 第1学期',
    courses: [
      ScheduleCourse(
        day: '星期${names[weekday - 1]}',
        title: '高等数学',
        teacher: '王老师',
        weeks: '1-16',
        sections: '1-2',
        location: '教3-201',
      ),
      ScheduleCourse(
        day: '星期${names[weekday - 1]}',
        title: '线性代数',
        teacher: '赵老师',
        weeks: '1-16',
        sections: '5-6',
        location: '教2-302',
      ),
    ],
  );
}

/// 一 / 二 / … for today, so the fixture lands on the right weekday.
final String _todayWeekdayName = const [
  '一',
  '二',
  '三',
  '四',
  '五',
  '六',
  '日',
][campusNow(DateTime.now()).weekday - 1];

/// [hour]:[minute] campus time today, as a local instant.
DateTime at(int hour, int minute) {
  final today = campusNow(DateTime.now());
  return DateTime.utc(
    today.year,
    today.month,
    today.day,
    hour - 8,
    minute,
  ).toLocal();
}

void main() {
  final schedule = _todaySchedule();
  final calendar = schedule.calendar!;

  WidgetSnapshot buildAt(int hour, int minute) => WidgetSnapshotBuilder().build(
    schedule: schedule,
    calendar: calendar,
    now: at(hour, minute),
  );

  test('timeline advances at course boundaries, midnight, and expires', () {
    final calendar = AcademicCalendar(
      term: '2026-2027-1',
      firstMonday: DateTime.utc(2026, 8, 31),
      weekCount: 19,
      sections: const [SectionTime(1, 600, 645)],
    );
    final schedule = Schedule(
      term: calendar.term,
      courses: const [
        ScheduleCourse(day: '星期一', title: '周一课', weeks: '1-19', sections: '1'),
        ScheduleCourse(day: '星期二', title: '周二课', weeks: '1-19', sections: '1'),
      ],
    );
    final payload = const WidgetSnapshotBuilder().timeline(
      schedule: schedule,
      calendar: calendar,
      now: DateTime.utc(2026, 10, 5, 1),
    );
    final entries = payload['entries'] as List;
    Map state(DateTime time) => entries.cast<Map>().lastWhere(
      (entry) => (entry['at'] as int) <= time.millisecondsSinceEpoch,
    );
    expect(state(DateTime.utc(2026, 10, 5, 1))['status'], 'upcoming');
    expect(state(DateTime.utc(2026, 10, 5, 2))['status'], 'in_class');
    expect(state(DateTime.utc(2026, 10, 5, 2, 45))['status'], 'done');
    expect(state(DateTime.utc(2026, 10, 5, 15, 59))['title'], '');
    expect(state(DateTime.utc(2026, 10, 5, 16))['title'], '周二课');
    expect(state(DateTime.utc(2026, 10, 6, 16))['status'], 'free');
    expect(
      payload['expiresAt'],
      DateTime.utc(2026, 10, 11, 16).millisecondsSinceEpoch,
    );
    expect(entries.length, lessThan(100));
  });

  group('WidgetSnapshotBuilder', () {
    test('shows the class in progress, with progress and minutes left', () {
      final snapshot = buildAt(8, 30);
      expect(snapshot.status, WidgetStatus.inClass);
      expect(snapshot.title, '高等数学');
      expect(snapshot.timeRange, '08:00 - 09:40');
      expect(snapshot.progress, closeTo(0.3, 0.02));
      expect(snapshot.minutes, 70);
      expect(snapshot.subtitle, '教3-201 · 王老师');
      expect(snapshot.week, isNotNull);
    });

    test('progress starts at 0 and never exceeds 1', () {
      expect(buildAt(8, 0).progress, closeTo(0, 0.001));
      expect(buildAt(9, 39).progress, greaterThan(0.98));
      expect(buildAt(9, 39).progress, lessThanOrEqualTo(1));
    });

    test('before the first class it points at the next one', () {
      final snapshot = buildAt(7, 30);
      expect(snapshot.status, WidgetStatus.upcoming);
      expect(snapshot.minutes, 30);
      expect(snapshot.progress, isNull);
      expect(snapshot.title, '高等数学');
    });

    test('in a gap it points at the next class of the day', () {
      final snapshot = buildAt(9, 50);
      expect(snapshot.status, WidgetStatus.upcoming);
      expect(snapshot.title, '线性代数');
      expect(snapshot.timeRange, '14:00 - 15:40');
      expect(snapshot.minutes, 250);
    });

    test('after the last class the day reads as done', () {
      final snapshot = buildAt(23, 30);
      expect(snapshot.status, WidgetStatus.done);
      expect(snapshot.title, isEmpty);
    });

    test('without a calendar it shows nothing rather than guessing', () {
      final snapshot = WidgetSnapshotBuilder().build(
        schedule: schedule,
        calendar: null,
        now: at(8, 30),
      );
      expect(snapshot.status, WidgetStatus.idle);
      expect(snapshot.title, isEmpty);
    });

    test('a schedule from another term shows nothing', () {
      final snapshot = WidgetSnapshotBuilder().build(
        schedule: Schedule(
          term: '2019-2020-1',
          courses: const [
            ScheduleCourse(day: '星期一', title: '古诗文鉴赏', sections: '1-2'),
          ],
        ),
        calendar: calendar,
        now: at(8, 30),
      );
      expect(snapshot.status, WidgetStatus.idle);
    });

    test('the skin colour travels with the snapshot', () {
      final snapshot = WidgetSnapshotBuilder(
        accent: ThemeSkin.rouge.color.toARGB32(),
      ).build(schedule: schedule, calendar: calendar, now: at(8, 30));
      expect(snapshot.accent, ThemeSkin.rouge.color.toARGB32());
    });

    test('carries the home card\'s pill, countdown and meta row', () {
      final inClass = buildAt(8, 30);
      expect(inClass.label, '正在上课');
      expect(inClass.trailing, '还剩 1 小时 10 分钟');
      // The room is not in the meta row: it draws on its own line.
      expect(inClass.metaTexts, ['08:00–09:40', '王老师']);
      expect(inClass.metaIcons, ['schedule', 'person']);
      expect(inClass.where, '教3-201');

      final next = buildAt(7, 30);
      expect(next.label, '下一节');
      expect(next.trailing, '还有 30 分钟');
      // Far-off classes read as a clock time instead of a long countdown.
      expect(buildAt(9, 50).trailing, '14:00 开始');
    });

    test('the meta row drops what the timetable does not have', () {
      final bare = WidgetSnapshotBuilder().build(
        schedule: Schedule(
          term: calendar.term,
          calendar: calendar,
          calendarStatus: 'confirmed',
          courses: [
            ScheduleCourse(
              day: _todayWeekdayName,
              title: '自习',
              weeks: '1-16',
              sections: '1-2',
            ),
          ],
        ),
        calendar: calendar,
        now: at(8, 30),
      );
      expect(bare.metaTexts, ['08:00–09:40']);
      expect(bare.metaIcons, ['schedule']);
      expect(bare.where, '');
    });

    test('the snapshot survives a JSON round trip', () {
      final snapshot = buildAt(8, 30);
      final restored = WidgetSnapshot.fromJson(
        Map<String, dynamic>.from(snapshot.toJson()),
      );
      expect(restored.status, snapshot.status);
      expect(restored.title, snapshot.title);
      expect(restored.subtitle, snapshot.subtitle);
      expect(restored.timeRange, snapshot.timeRange);
      expect(restored.progress, closeTo(snapshot.progress!, 0.0001));
      expect(restored.minutes, snapshot.minutes);
      expect(restored.accent, snapshot.accent);
      expect(restored.label, snapshot.label);
      expect(restored.trailing, snapshot.trailing);
      expect(restored.metaTexts, snapshot.metaTexts);
      expect(restored.metaIcons, snapshot.metaIcons);
    });

    test('a payload with junk values still decodes into something safe', () {
      final restored = WidgetSnapshot.fromJson(const {
        'status': 'nonsense',
        'title': '高数',
      });
      expect(restored.status, WidgetStatus.idle);
      expect(restored.accent, 0xFF1D6FD8);
      expect(restored.progress, isNull);
      expect(restored.minutes, isNull);
    });
  });

  group('WidgetBridge', () {
    testWidgets('pushes a snapshot once the timetable is loaded', (
      tester,
    ) async {
      final host = MemoryWidgetHost();
      final app = await pumpTestApp(
        tester,
        repository: FakeAuthRepository(stored: testSession()),
        campusRepository: UiCampusRepository(),
        widgetHost: host,
      );

      await app.campus.loadSchedule();
      await tester.pumpAndSettle();

      expect(host.synced, isNotEmpty);
      expect(host.synced.last['status'], isNotNull);
    });

    testWidgets(
      'history never replaces the home term and logout cannot republish courses',
      (tester) async {
        final host = MemoryWidgetHost();
        final app = await pumpTestApp(
          tester,
          repository: FakeAuthRepository(stored: testSession()),
          campusRepository: UiCampusRepository(),
          widgetHost: host,
        );
        final homeSchedule = app.campus.home.schedule.state.data;
        final history = app.campus.loadSchedule(term: '2019-2020-1');
        await tester.pumpAndSettle();
        await history;
        expect(app.campus.widgetSource.widgetSchedule, same(homeSchedule));
        await signOutFromMine(tester);
        final count = host.synced.length;
        await tester.pump(const Duration(minutes: 2));
        expect(host.synced.length, count);
        expect(host.cleared, greaterThan(0));
      },
    );

    testWidgets('signing out clears the widget', (tester) async {
      final host = MemoryWidgetHost();
      await pumpTestApp(
        tester,
        repository: FakeAuthRepository(stored: testSession()),
        campusRepository: UiCampusRepository(),
        widgetHost: host,
      );
      await signOutFromMine(tester);
      expect(host.cleared, greaterThan(0));
    });

    testWidgets('the chosen skin is the colour the widget uses', (
      tester,
    ) async {
      final host = MemoryWidgetHost();
      final theme = ThemeSettings(MemoryThemeStore());
      await pumpTestApp(
        tester,
        repository: FakeAuthRepository(stored: testSession()),
        campusRepository: UiCampusRepository(),
        themeSettings: theme,
        widgetHost: host,
      );

      theme.setSkin(ThemeSkin.lakeTeal);
      await tester.pumpAndSettle();
      expect(host.synced.last['accent'], ThemeSkin.lakeTeal.color.toARGB32());
    });
  });
}
