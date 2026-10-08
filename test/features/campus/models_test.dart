import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import 'support.dart';

void main() {
  test('electricity notices hide empty HTML and preserve readable text', () {
    String tip(String? value) => ElectricityRechargeConfig.fromJson({
      ...example('newcard.electricity.recharge.config'),
      'tip': value,
    }).tip;
    for (final empty in [
      null,
      '',
      '<p><br></p>',
      '<p>&nbsp; &#160; &#x200B;</p>',
      '<!-- empty --><style>p { color: red; }</style><script>code()</script>',
    ]) {
      expect(tip(empty), isEmpty);
    }
    expect(
      tip('<p>充值后<b>请等待</b><br>到账</p><p>金额 &gt; 0</p>'),
      '充值后请等待\n到账\n金额 > 0',
    );
    expect(tip('  请确认宿舍号  '), '请确认宿舍号');
  });

  test('decimal amounts are exact and invalid amounts are rejected', () {
    expect(MoneyAmount.parse(' 00050.1 ').value, '50.10');
    expect(MoneyAmount.parse('0.01').value, '0.01');
    for (final input in ['0', '0.00', '-1', '1.001', 'NaN', '1e2', '', '.1']) {
      expect(() => MoneyAmount.parse(input), throwsA(isA<CampusFailure>()));
    }
  });
  test(
    'scores preserve nonnumeric grades and missing numbers are not zero',
    () {
      final grade = Grade.fromJson({'courseName': '体育', 'score': '优秀'});
      expect(grade.score, '优秀');
      expect(grade.numericScore, isNull);
      expect(grade.numericCredit, isNull);
      expect(() => Grades.fromJson({}), throwsA(isA<CampusFailure>()));
      final grades = Grades.fromJson(example('jw.grades'));
      expect(() => grades.normalGrades.clear(), throwsUnsupportedError);
    },
  );
  test('date and pagination validation occurs before a request', () {
    expect(
      () => const TransactionQuery(pageSize: 101).params(1),
      throwsA(isA<CampusFailure>()),
    );
    expect(
      () => TransactionQuery(
        fromDate: DateTime(2026, 10, 8),
        toDate: DateTime(2026, 10, 7),
      ).params(1),
      throwsA(isA<CampusFailure>()),
    );
    expect(
      TransactionQuery(fromDate: DateTime(2026, 1, 2)).params(1)['fromDate'],
      '2026-01-02',
    );
  });
  test(
    'WeChat official transfer URL takes priority; fallback uses documented referer',
    () {
      final result = PaymentResult.fromJson({
        'type': 'h5_url',
        'payCode': '02',
        'h5Url': 'https://pay.example.test/pay',
      });
      expect(result.h5Headers, {'Referer': 'https://newcard.xjit.edu.cn/'});
      final official = PaymentResult.fromJson({
        'type': 'h5_url',
        'payCode': '02',
        'h5Url': 'https://pay.example.test/pay',
        'officialTransferUrl': 'https://newcard.xjit.edu.cn/transfer',
      });
      expect(official.preferredUrl!.path, '/transfer');
      expect(official.h5Headers, isEmpty);
      expect(
        () => PaymentResult.fromJson({
          'type': 'h5',
          'h5Url': 'javascript:alert(1)',
        }),
        throwsA(isA<CampusFailure>()),
      );
      expect(
        PaymentResult.fromJson({'type': 'future_type'}).type,
        PaymentResultType.unsupported,
      );
    },
  );
  test('Chinese weeks/sections parse ranges, odd/even and unknown syntax', () {
    expect(parseSchoolNumbers('1-8周（单）,10,12-14', weeks: true), {
      1,
      3,
      5,
      7,
      10,
      12,
      13,
      14,
    });
    expect(parseSchoolNumbers('1-16周(双)', weeks: true), {
      2,
      4,
      6,
      8,
      10,
      12,
      14,
      16,
    });
    expect(parseSchoolNumbers('1-2节'), {1, 2});
    expect(parseSchoolNumbers('待定', weeks: true), isNull);
    expect(parseSchoolNumbers('16-1周', weeks: true), isNull);
    expect(courseWeekday('星期日'), 7);
  });
  final calendar = AcademicCalendar(
    term: '2026-2027-1',
    firstMonday: DateTime.utc(2026, 9, 7),
    weekCount: 20,
    sections: const [
      SectionTime(1, 9 * 60, 9 * 60 + 45),
      SectionTime(2, 9 * 60 + 55, 10 * 60 + 40),
      SectionTime(3, 11 * 60, 11 * 60 + 45),
    ],
  );
  Schedule schedule({
    String weeks = '1-16周',
    String sections = '1-2节',
    String day = '星期一',
  }) => Schedule(
    term: calendar.term,
    courses: [
      ScheduleCourse(title: '数学', day: day, weeks: weeks, sections: sections),
    ],
  );
  const planner = SchedulePlanner();
  test('school time uses Asia/Shanghai independent of device timezone', () {
    final now = DateTime.parse(
      '2026-09-06T21:00:00-04:00',
    ); // Monday 09:00 CST.
    final day = planner.today(schedule(), calendar, now);
    expect(day.status, DayScheduleStatus.inClass);
    expect(day.week, 1);
    expect(day.current!.startsAt, DateTime.utc(2026, 9, 7, 1));
    expect(
      planner.today(schedule(), calendar, DateTime.utc(2026, 9, 7, 0)).status,
      DayScheduleStatus.upcoming,
    );
    expect(
      planner
          .today(schedule(), calendar, DateTime.utc(2026, 9, 7, 2, 40))
          .status,
      DayScheduleStatus.finished,
    );
  });
  test(
    'no calendar, unknown weeks, no classes and outside term are distinct',
    () {
      final now = DateTime.utc(2026, 9, 7);
      expect(
        planner.today(schedule(), null, now).status,
        DayScheduleStatus.needsCalendar,
      );
      expect(
        planner.today(schedule(weeks: '待定'), calendar, now).status,
        DayScheduleStatus.incomplete,
      );
      expect(
        planner.today(schedule(day: '周二'), calendar, now).status,
        DayScheduleStatus.noClasses,
      );
      expect(
        planner.today(schedule(), calendar, DateTime.utc(2026, 9, 6)).status,
        DayScheduleStatus.outsideTerm,
      );
      expect(
        planner.today(schedule(sections: '99'), calendar, now).status,
        DayScheduleStatus.incomplete,
      );
    },
  );
  test('noncontiguous sections do not claim class throughout the gap', () {
    final day = planner.today(
      schedule(sections: '1,3节'),
      calendar,
      DateTime.utc(2026, 9, 7, 2),
    );
    expect(day.courses.length, 2);
    expect(day.current, isNull);
    expect(day.next!.startsAt, DateTime.utc(2026, 9, 7, 3));
  });
  test('exam text uses strict dates and retains unknown format for UI', () {
    final exam = ExamOccurrence.parse(
      const Exam(courseName: '数学', examTime: '2026-10-08 09:00-11:00'),
    );
    expect(exam.startsAt, DateTime.utc(2026, 10, 8, 1));
    expect(
      ExamOccurrence.parse(
        const Exam(courseName: '数学', examTime: '2026-02-30 09:00-11:00'),
      ).startsAt,
      isNull,
    );
    expect(
      ExamOccurrence.parse(
        const Exam(courseName: '数学', examTime: '待定'),
      ).startsAt,
      isNull,
    );
  });
}
