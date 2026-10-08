import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import 'calendar_test.dart' show calendarJson;

// Anonymized reproduction of the live API's repeated fourth/fifth-slot rows.
Schedule spanningSchedule({bool distinctRooms = false}) => Schedule.fromJson({
  'term': '2026-2027-1',
  'calendarStatus': 'confirmed',
  'calendar': calendarJson(),
  'courses': [
    for (final slot in ['第四大节', '第五大节'])
      {
        'day': '星期三',
        'title': '跨四节课程',
        'teacher': '测试教师',
        'weeks': '7-16(周)',
        'sections': '07-08-09-10节',
        'slot': slot,
        'location': distinctRooms ? slot : '测试教室',
      },
  ],
});

// Backend-normalized full-day practice: retain all ten distinct meetings.
Schedule practiceSchedule() => Schedule.fromJson({
  'term': '2026-2027-1',
  'calendarStatus': 'confirmed',
  'calendar': calendarJson(),
  'courses': [
    for (final day in ['星期三', '星期四'])
      for (final sections in ['01-02节', '03-04节', '05-06节', '07-08节', '09-10节'])
        {
          'day': day,
          'title': '实践课程',
          'teacher': '测试教师',
          'weeks': '17-18(周)',
          'sections': sections,
          'location': '测试实验室',
          'originalSections': '01节',
          'sectionSource': 'timetable_slot',
        },
  ],
});

void main() {
  const planner = SchedulePlanner();

  test(
    'week seventeen practice retains five distinct periods on both days',
    () {
      final schedule = practiceSchedule();
      for (final week in [16, 17, 18, 19]) {
        for (var day = 1; day <= 7; day++) {
          final date = schedule.calendar!.firstMonday.add(
            Duration(days: (week - 1) * 7 + day - 1, hours: 4),
          );
          final plan = planner.today(schedule, schedule.calendar, date);
          final hasPractice = [17, 18].contains(week) && [3, 4].contains(day);
          expect(plan.courses, hasLength(hasPractice ? 5 : 0));
          expect(plan.unresolved, isEmpty);
          if (hasPractice) {
            expect(plan.courses.map((c) => campusNow(c.startsAt).hour), [
              10,
              12,
              16,
              18,
              20,
            ]);
            expect(plan.courses.map((c) => campusNow(c.endsAt).hour), [
              11,
              13,
              17,
              19,
              22,
            ]);
            for (var i = 1; i < plan.courses.length; i++) {
              expect(
                plan.courses[i].startsAt.isAfter(plan.courses[i - 1].endsAt),
                isTrue,
              );
            }
          }
        }
      }
    },
  );

  test('school hyphen enumeration parses sections without inventing gaps', () {
    expect(parseSchoolNumbers('07-08-09-10节'), {7, 8, 9, 10});
    expect(parseSchoolNumbers('01-02-05-06节'), {1, 2, 5, 6});
    expect(parseSchoolNumbers('07-08节'), {7, 8});
    expect(parseSchoolNumbers('1-16(单周)', weeks: true), {
      1,
      3,
      5,
      7,
      9,
      11,
      13,
      15,
    });
    expect(parseSchoolNumbers('07-08-09-10', weeks: true), isNull);
    for (final value in [
      '07-08-07节',
      '07-08-08节',
      '00-01-02节',
      '29-30-31节',
      '07--08-09节',
    ]) {
      expect(parseSchoolNumbers(value), isNull);
    }
  });

  test(
    'week seven spanning class appears exactly once with correct bounds',
    () {
      final schedule = spanningSchedule();
      final day = planner.today(
        schedule,
        schedule.calendar,
        DateTime.utc(2026, 10, 14, 4),
      );
      expect(day.week, 7);
      expect(day.unresolved, isEmpty);
      expect(day.courses, hasLength(1));
      expect(day.courses.single.startsAt, DateTime.utc(2026, 10, 14, 10));
      expect(day.courses.single.endsAt, DateTime.utc(2026, 10, 14, 14, 10));
      expect(
        planner
            .today(schedule, schedule.calendar, DateTime.utc(2026, 10, 7, 4))
            .courses,
        isEmpty,
      );
      expect(
        planner
            .today(schedule, schedule.calendar, DateTime.utc(2026, 12, 23, 4))
            .courses,
        isEmpty,
      );
    },
  );

  test('same title at different locations is still a real conflict', () {
    final schedule = spanningSchedule(distinctRooms: true);
    final day = planner.today(
      schedule,
      schedule.calendar,
      DateTime.utc(2026, 10, 14, 4),
    );
    expect(day.courses, hasLength(2));
    expect(day.unresolved, isEmpty);
  });

  test('enumerated noncontiguous sections remain separate meetings', () {
    final schedule = Schedule.fromJson({
      'term': '2026-2027-1',
      'calendarStatus': 'confirmed',
      'calendar': calendarJson(),
      'courses': [
        {
          'title': '分段课程',
          'day': '星期三',
          'weeks': '7-16(周)',
          'sections': '01-02-05-06节',
        },
      ],
    });
    final day = planner.today(
      schedule,
      schedule.calendar,
      DateTime.utc(2026, 10, 14, 4),
    );
    expect(day.courses, hasLength(2));
    expect(day.current, isNull);
    expect(day.unresolved, isEmpty);
  });
}
