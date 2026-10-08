import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/campus/campus.dart';
import 'package:xinli_lite/features/campus/application/course_activity_controller.dart';
import 'package:xinli_lite/features/campus/domain/course_reminder_plan.dart';

import '../../support/fakes.dart';

AcademicCalendar calendar({List<CalendarDateOverride> overrides = const []}) =>
    AcademicCalendar(
      term: '2026-2027-1',
      firstMonday: DateTime.utc(2026, 8, 31),
      weekCount: 19,
      sections: const [
        SectionTime(7, 1080, 1125),
        SectionTime(8, 1135, 1180),
        SectionTime(9, 1230, 1275),
        SectionTime(10, 1285, 1330),
      ],
      dateOverrides: overrides,
    );

const course = ScheduleCourse(
  day: '星期一',
  title: '实验课',
  teacher: '老师',
  weeks: '1-19',
  sections: '07-08-09-10节',
  location: '实验楼101',
);

class Source extends ChangeNotifier implements WidgetScheduleSource {
  @override
  AcademicCalendar? widgetCalendar = calendar();
  @override
  Schedule? widgetSchedule = Schedule(term: '2026-2027-1', courses: [course]);
}

class Host implements CourseActivityHost {
  final calls = <String>[];
  Future<Map<String, dynamic>> Function(String)? respond;
  @override
  Future<Map<String, dynamic>> invoke(
    String method,
    Map<String, Object?> args,
  ) async {
    calls.add(method);
    return await respond?.call(method) ??
        {'testing': method == 'startTest', 'phase': 'pending'};
  }
}

void main() {
  test(
    'four continuous sections become two major classes; duplicates collapse',
    () {
      final items = const CourseReminderPlanner().build(
        schedule: Schedule(term: '2026-2027-1', courses: [course, course]),
        calendar: calendar(),
        now: DateTime.utc(2026, 10, 5),
        days: 1,
      );
      expect(items, hasLength(2));
      expect(items[0].showAt, DateTime.utc(2026, 10, 5, 9, 45));
      expect(items[0].startsAt, DateTime.utc(2026, 10, 5, 10));
      expect(items[0].dismissAt, DateTime.utc(2026, 10, 5, 10, 1));
      expect(items[1].startsAt, DateTime.utc(2026, 10, 5, 12, 30));
      expect(items[1].endsAt, DateTime.utc(2026, 10, 5, 14, 10));
      final again = const CourseReminderPlanner().build(
        schedule: Schedule(term: '2026-2027-1', courses: [course]),
        calendar: calendar(),
        now: DateTime.utc(2026, 10, 5),
        days: 1,
      );
      expect(items.map((e) => e.id), again.map((e) => e.id));
    },
  );

  test('respect cancellation, rescheduling, expiry and current term', () {
    final schedule = Schedule(term: '2026-2027-1', courses: [course]);
    final cal = calendar(
      overrides: [
        CalendarDateOverride(
          date: DateTime.utc(2026, 10, 5),
          scheduleDate: null,
          reason: '放假',
        ),
        CalendarDateOverride(
          date: DateTime.utc(2026, 10, 6),
          scheduleDate: DateTime.utc(2026, 10, 5),
          reason: '补课',
        ),
      ],
    );
    final items = const CourseReminderPlanner().build(
      schedule: schedule,
      calendar: cal,
      now: DateTime.utc(2026, 10, 5),
      days: 2,
    );
    expect(items, hasLength(2));
    expect(items.first.startsAt, DateTime.utc(2026, 10, 6, 10));
    expect(
      const CourseReminderPlanner().build(
        schedule: schedule,
        calendar: calendar(),
        now: DateTime.utc(2026, 10, 5, 10, 1),
        days: 1,
      ),
      hasLength(1),
    );
    expect(
      const CourseReminderPlanner().build(
        schedule: Schedule(term: 'old', courses: [course]),
        calendar: cal,
        now: DateTime.utc(2026, 10, 5),
      ),
      isEmpty,
    );
  });

  test(
    'aggregate calendar pairs work without inventing partial section times',
    () {
      final cal = AcademicCalendar(
        term: '2026-2027-1',
        firstMonday: DateTime.utc(2026, 8, 31),
        weekCount: 19,
        sections: const [
          SectionTime(7, 1080, 1180, endSection: 8),
          SectionTime(9, 1230, 1330, endSection: 10),
        ],
      );
      expect(
        const CourseReminderPlanner().build(
          schedule: Schedule(term: cal.term, courses: [course]),
          calendar: cal,
          now: DateTime.utc(2026, 10, 5),
          days: 1,
        ),
        hasLength(2),
      );
      expect(
        const CourseReminderPlanner().build(
          schedule: Schedule(
            term: cal.term,
            courses: const [
              ScheduleCourse(
                day: '星期一',
                title: '不明确',
                weeks: '1-19',
                sections: '8',
              ),
            ],
          ),
          calendar: cal,
          now: DateTime.utc(2026, 10, 5),
          days: 1,
        ),
        isEmpty,
      );
    },
  );

  for (final username in ['20230001', '202303310112']) {
    test('test entry and business authorization for $username', () async {
      final auth = AuthController(
        repository: FakeAuthRepository(stored: testSession(username: username)),
      );
      final source = Source();
      final host = Host();
      final controller = CourseActivityController(
        auth: auth,
        source: source,
        host: host,
        supportedPlatform: true,
      );
      await auth.restore();
      await controller.setTesting(true);
      expect(
        controller.canTest,
        username == CourseActivityController.testerUsername,
      );
      expect(
        host.calls.contains('startTest'),
        username == CourseActivityController.testerUsername,
      );
      controller.dispose();
      source.dispose();
      auth.dispose();
    });
  }

  test(
    'logout serializes cleanup after an in-flight start; late result cannot turn switch on',
    () async {
      final auth = AuthController(
        repository: FakeAuthRepository(
          stored: testSession(username: '202303310112'),
        ),
      );
      await auth.restore();
      final source = Source();
      final host = Host();
      final started = Completer<void>();
      final response = Completer<Map<String, dynamic>>();
      host.respond = (method) async {
        if (method == 'startTest') {
          started.complete();
          return response.future;
        }
        return {'testing': false};
      };
      final controller = CourseActivityController(
        auth: auth,
        source: source,
        host: host,
        supportedPlatform: true,
      );
      final start = controller.setTesting(true);
      await started.future;
      await auth.signOut();
      response.complete({'testing': true});
      await start;
      await Future<void>.delayed(Duration.zero);
      expect(host.calls.last, 'session');
      expect(controller.testing, isFalse);
      expect(controller.canTest, isFalse);
      controller.dispose();
      source.dispose();
      auth.dispose();
    },
  );

  test(
    'native permission errors are visible and do not leave switch on or busy',
    () async {
      final auth = AuthController(
        repository: FakeAuthRepository(
          stored: testSession(username: '202303310112'),
        ),
      );
      await auth.restore();
      final source = Source();
      final host = Host()
        ..respond = (method) async {
          if (method == 'startTest') {
            throw PlatformException(code: 'disabled', message: '请允许实时活动');
          }
          return {'testing': false};
        };
      final controller = CourseActivityController(
        auth: auth,
        source: source,
        host: host,
        supportedPlatform: true,
      );
      await controller.setTesting(true);
      expect(controller.error, '请允许实时活动');
      expect(controller.testing, isFalse);
      expect(controller.busy, isFalse);
      controller.dispose();
      source.dispose();
      auth.dispose();
    },
  );
}
