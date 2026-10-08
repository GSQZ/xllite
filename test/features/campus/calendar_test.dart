import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import 'support.dart';

Map<String, dynamic> calendarJson() =>
    jsonDecode(
          File(
            'test/features/campus/fixtures/academic-calendar.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
Schedule scheduleJson({
  Map<String, dynamic>? calendar,
  String sections = '1-2节',
  String weeks = '1-18周',
  String weekday = '星期一',
  String term = '2026-2027-1',
}) => Schedule.fromJson({
  'term': term,
  'calendarStatus': 'confirmed',
  'calendar': calendar ?? calendarJson(),
  'courses': [
    {'title': '数学', 'day': weekday, 'weeks': weeks, 'sections': sections},
  ],
});

void main() {
  const planner = SchedulePlanner();
  test(
    'backend config activates home calendar without manual UI setup',
    () async {
      final repo = FakeCampusRepository()
        ..onSchedule = (_) async => scheduleJson();
      final profile = ResourceController<StudentProfile>('profile');
      final exams = ResourceController<List<Exam>>('exams');
      final home = HomeController(
        repo,
        profile: profile,
        exams: exams,
        now: () => DateTime.utc(2026, 8, 31, 2),
      );
      addTearDown(() {
        home.dispose();
        profile.dispose();
        exams.dispose();
      });
      await home.load();
      expect(home.calendar!.firstMonday, DateTime.utc(2026, 8, 31));
      expect(home.state.day!.week, 1);
      expect(home.state.day!.status, DayScheduleStatus.inClass);
      home.resetSession();
      expect(home.calendar, isNull);
    },
  );
  test('week six on October 8 and semester end includes examination week', () {
    final calendar = AcademicCalendar.fromJson(calendarJson());
    expect(calendar.weekOn(DateTime.utc(2026, 10, 8)), 6);
    expect(calendar.weekOn(DateTime.utc(2027, 1, 10)), 19);
    expect(calendar.weekOn(DateTime.utc(2027, 1, 11)), isNull);
    expect(calendar.freshmanClassesStartOn, DateTime.utc(2026, 9, 14));
  });
  test('all ten small periods have exact user-confirmed timing', () {
    final pairs = [
      (600, 645),
      (655, 700),
      (720, 765),
      (775, 820),
      (960, 1005),
      (1015, 1060),
      (1080, 1125),
      (1135, 1180),
      (1230, 1275),
      (1285, 1330),
    ];
    for (var n = 1; n <= 10; n++) {
      final schedule = scheduleJson(sections: '$n节');
      final day = planner.today(
        schedule,
        schedule.calendar,
        DateTime.utc(2026, 8, 31),
      );
      expect(
        day.courses.single.startsAt,
        DateTime.utc(2026, 8, 31).add(Duration(minutes: pairs[n - 1].$1 - 480)),
      );
      expect(
        day.courses.single.endsAt
            .difference(day.courses.single.startsAt)
            .inMinutes,
        45,
      );
    }
    final evening = scheduleJson(sections: '9-10节');
    final day = planner.today(
      evening,
      evening.calendar,
      DateTime.utc(2026, 8, 31, 12, 30),
    );
    expect(day.status, DayScheduleStatus.inClass);
    expect(day.courses.single.endsAt, DateTime.utc(2026, 8, 31, 14, 10));
  });
  test(
    'unconfigured, malformed and mismatched calendar retain original courses',
    () {
      for (final c in [
        <String, dynamic>{},
        {...calendarJson(), 'term': '2026-2027-2'},
        {...calendarJson(), 'timezone': 'UTC'},
        {...calendarJson(), 'firstMonday': '2026-02-30'},
      ]) {
        final schedule = scheduleJson(calendar: c);
        expect(schedule.courses.single.title, '数学');
        expect(schedule.calendar, isNull);
        expect(schedule.calendarStatus, 'unavailable');
      }
      final old = Schedule.fromJson({'term': '2025-2026-2', 'courses': []});
      expect(old.calendarStatus, 'unconfigured');
      expect(old.calendar, isNull);
    },
  );
  test('whole-period published ranges never invent partial-period times', () {
    final json = calendarJson()
      ..['sectionTimes'] = [
        {
          'startSection': 1,
          'endSection': 2,
          'startTime': '10:00',
          'endTime': '11:40',
        },
      ];
    final full = scheduleJson(calendar: json);
    expect(
      planner
          .today(full, full.calendar, DateTime.utc(2026, 8, 31))
          .courses
          .single
          .endsAt,
      DateTime.utc(2026, 8, 31, 3, 40),
    );
    final partial = scheduleJson(calendar: json, sections: '2节');
    expect(
      planner
          .today(partial, partial.calendar, DateTime.utc(2026, 8, 31))
          .status,
      DayScheduleStatus.incomplete,
    );
  });
  test(
    'makeup day uses source weekday AND week but actual destination time',
    () {
      final json = calendarJson()
        ..['dateOverrides'] = [
          {'date': '2026-10-01', 'scheduleDate': null, 'reason': '停课'},
          {
            'date': '2026-10-10',
            'scheduleDate': '2026-10-01',
            'reason': '补周五前的周四课',
          },
        ];
      final schedule = scheduleJson(
        calendar: json,
        weekday: '星期四',
        weeks: '5周',
      );
      final holiday = planner.today(
        schedule,
        schedule.calendar,
        DateTime.utc(2026, 10, 1, 2),
      );
      expect(holiday.status, DayScheduleStatus.noClasses);
      final makeup = planner.today(
        schedule,
        schedule.calendar,
        DateTime.utc(2026, 10, 10, 2),
      );
      expect(makeup.week, 6);
      expect(makeup.status, DayScheduleStatus.inClass);
      expect(makeup.courses.single.startsAt, DateTime.utc(2026, 10, 10, 2));
    },
  );
  test('bad time ordering and duplicate overrides reject calendar only', () {
    final json = calendarJson();
    (json['sectionTimes'] as List)[1]['startTime'] = '10:30';
    expect(scheduleJson(calendar: json).calendar, isNull);
    final overrides = calendarJson()
      ..['dateOverrides'] = [
        {'date': '2026-10-01', 'scheduleDate': null, 'reason': 'a'},
        {'date': '2026-10-01', 'scheduleDate': null, 'reason': 'b'},
      ];
    expect(scheduleJson(calendar: overrides).calendar, isNull);
  });
}
