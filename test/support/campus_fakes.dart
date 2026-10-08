import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/campus/campus.dart';
import 'package:xinli_lite/features/campus/presentation/home_shell.dart';

const testProfile = StudentProfile(
  studentId: '20230001',
  name: '张三',
  college: '信息工程学院',
  major: '软件工程',
  className: '软件2301',
  grade: '2023',
);

Schedule testSchedule({String term = '2026-2027-1'}) => Schedule(
  term: term,
  courses: const [
    ScheduleCourse(
      day: '星期一',
      title: '高等数学',
      teacher: '王老师',
      weeks: '1-16',
      sections: '1-2',
      location: '教3-201',
    ),
    ScheduleCourse(
      day: '星期三',
      title: '大学英语',
      teacher: '李老师',
      weeks: '1-16',
      sections: '3-4',
      location: '教1-105',
    ),
  ],
);

/// A term whose current teaching week is 6, with a fixed bell schedule.
AcademicCalendar testCalendar({
  String term = '2026-2027-1',
  List<CalendarDateOverride> overrides = const [],
}) {
  final today = campusNow(DateTime.now());
  final monday = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).subtract(Duration(days: today.weekday - 1 + 35));
  return AcademicCalendar(
    term: term,
    firstMonday: monday,
    weekCount: 18,
    sections: const [
      SectionTime(1, 480, 525),
      SectionTime(2, 535, 580),
      SectionTime(3, 600, 645),
      SectionTime(4, 655, 700),
      SectionTime(5, 840, 885),
      SectionTime(6, 895, 940),
    ],
    dateOverrides: overrides,
  );
}

const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

/// Monday 高等数学 1-2, Wednesday 大学英语 3-4, and today's 线性代数 5-6
/// (weeks 1-6 only), with [calendar] attached.
Schedule testCalendarSchedule({AcademicCalendar? calendar}) {
  final today = campusNow(DateTime.now()).weekday;
  return Schedule(
    term: '2026-2027-1',
    calendar: calendar ?? testCalendar(),
    calendarStatus: 'confirmed',
    termLabel: '2026–2027学年 第1学期',
    courses: [
      const ScheduleCourse(
        day: '星期一',
        title: '高等数学',
        teacher: '王老师',
        weeks: '1-16',
        sections: '1-2',
        location: '教3-201',
      ),
      const ScheduleCourse(
        day: '星期三',
        title: '大学英语',
        teacher: '李老师',
        weeks: '1-16',
        sections: '3-4',
        location: '教1-105',
      ),
      ScheduleCourse(
        day: '星期${_weekdayNames[today - 1]}',
        title: '线性代数',
        teacher: '赵老师',
        weeks: '1-6',
        sections: '5-6',
        location: '教2-302',
      ),
    ],
  );
}

ElectricityAccount testElectricity({String value = '28.15'}) =>
    ElectricityAccount.fromJson({
      'remainingElectricity': {'value': value, 'unit': '度'},
      'room': {
        'query': '9#312',
        'buildingName': '9号宿舍楼',
        'levelName': '3层',
        'roomName': '312房间',
      },
    });

Grades testGrades() => Grades.fromJson({
  'mode': 'best_by_course',
  'summary': {
    'courseCount': 3,
    'totalCredits': 9.5,
    'gpaCredits': 9.5,
    'weightedGradePoint': 3.12,
    'failedCourseCount': 1,
    'failedCredits': 3,
  },
  'rawSummary': {
    'courseCount': 4,
    'totalCredits': 12.5,
    'gpaCredits': 12.5,
    'weightedGradePoint': 2.8,
    'failedCourseCount': 2,
    'failedCredits': 6,
  },
  'terms': [
    {
      'term': '2025-2026-1',
      'courseCount': 1,
      'totalCredits': 3,
      'gpaCredits': 0,
      'weightedGradePoint': null,
      'failedCourseCount': 1,
      'failedCredits': 3,
    },
    {
      'term': '2025-2026-2',
      'courseCount': 2,
      'totalCredits': 6.5,
      'gpaCredits': 6.5,
      'weightedGradePoint': 3.5,
      'failedCourseCount': 0,
      'failedCredits': 0,
    },
  ],
  'normalGrades': [
    {
      'term': '2025-2026-2',
      'courseCode': 'C1',
      'courseName': '数据结构',
      'score': '92',
      'credit': '3.5',
      'gradePoint': '4.2',
      'examNature': '正常考试',
      'source': 'gradeList',
    },
    {
      'term': '2025-2026-2',
      'courseCode': 'C2',
      'courseName': '体育',
      'score': '优秀',
      'credit': '3',
      'examNature': '正常考试',
      'source': 'graduationAudit',
    },
    {
      'term': '2025-2026-1',
      'courseCode': 'C3',
      'courseName': '高等数学',
      'score': '45',
      'credit': '3',
      'gradePoint': '0',
      'examNature': '正常考试',
      'source': 'gradeList',
    },
  ],
  'makeupGrades': [],
  'failedCourses': [
    {
      'term': '2025-2026-1',
      'courseCode': 'C3',
      'courseName': '高等数学',
      'score': '45',
      'credit': '3',
    },
  ],
  'sourceSummary': {
    'gradeListCount': 2,
    'graduationAuditCount': 1,
    'addedFromGraduationAuditCount': 1,
  },
});

/// A transactions page; [count] items numbered from [first].
TransactionPage testTransactions({
  int pageNo = 1,
  int count = 20,
  int first = 1,
  int pageSize = 20,
}) => TransactionPage.fromJson({
  'fromDate': '2026-09-08',
  'toDate': '2026-10-08',
  'tradeType': '1,2,3',
  'pageNo': pageNo,
  'pageSize': pageSize,
  'transactions': [
    for (var i = first; i < first + count; i++)
      {
        'date':
            '2026-10-${(8 - i ~/ 10).toString().padLeft(2, '0')} 12:${(i % 60).toString().padLeft(2, '0')}:00',
        'summary': '消费',
        'merchantName': '第$i食堂窗口',
        'amount': '-${(i + 0.5).toStringAsFixed(2)}',
        'isRefund': i == 2 ? '是' : '否',
        'journo': 'J$i',
      },
  ],
});

CampusCode testCampusCode({String value = 'PAY-CODE-1', int seconds = 30}) =>
    CampusCode.fromJson({
      'mode': 'online',
      'qrcode': value,
      'qrcodeType': '',
      'expiresInSeconds': seconds,
      'balance': '128.50',
      'idSerial': '20230001',
      'userName': '张三',
      'displayInfo': true,
      'displayBalance': true,
    }, requestedAt: DateTime.now());

/// In-memory [CampusRepository] for UI tests. Each read defaults to instant
/// sample data; tests swap hooks to delay or fail a single module.
class UiCampusRepository implements CampusRepository {
  Future<StudentProfile> Function()? onProfile;
  Future<Schedule> Function(String? term)? onSchedule;
  Future<List<Exam>> Function()? onExams;
  Future<List<CardAccount>> Function()? onBalance;
  Future<ElectricityAccount> Function(String room)? onElectricity;
  Future<Grades> Function()? onGrades;
  Future<TransactionPage> Function(TransactionQuery query, int pageNo)?
  onTransactions;
  Future<CampusCode> Function()? onCampusCode;

  int gradesCalls = 0, codeCalls = 0;
  final transactionCalls = <(TransactionQuery, int)>[];

  int profileCalls = 0, scheduleCalls = 0, examCalls = 0, balanceCalls = 0;
  final electricityRooms = <String>[];

  @override
  Future<StudentProfile> profile() {
    profileCalls++;
    return onProfile?.call() ?? Future.value(testProfile);
  }

  @override
  Future<Schedule> schedule({String? term}) {
    scheduleCalls++;
    return onSchedule?.call(term) ?? Future.value(testSchedule());
  }

  @override
  Future<List<Exam>> exams() {
    examCalls++;
    return onExams?.call() ?? Future.value(const []);
  }

  @override
  Future<List<CardAccount>> balance() {
    balanceCalls++;
    return onBalance?.call() ??
        Future.value(const [CardAccount(balance: '128.50', unit: '元')]);
  }

  @override
  Future<ElectricityAccount> electricity(String roomQuery) {
    electricityRooms.add(roomQuery);
    return onElectricity?.call(roomQuery) ?? Future.value(testElectricity());
  }

  @override
  Future<Grades> grades({
    String? term,
    GradeMode mode = GradeMode.bestByCourse,
  }) {
    gradesCalls++;
    return onGrades?.call() ?? Future.value(testGrades());
  }

  @override
  Future<TransactionPage> transactions(
    TransactionQuery query, {
    int pageNo = 1,
  }) {
    transactionCalls.add((query, pageNo));
    return onTransactions?.call(query, pageNo) ??
        Future.value(
          pageNo == 1
              ? testTransactions()
              : testTransactions(pageNo: pageNo, count: 5, first: 21),
        );
  }

  @override
  Future<CampusCode> campusCode({String qrcodeType = '', String? devCode}) {
    codeCalls++;
    return onCampusCode?.call() ?? Future.value(testCampusCode());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not used by UI tests',
  );
}

/// The signed-in shell is on screen.
Finder get homeShell => find.byType(HomeShell);

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('home.nav')),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

/// Goes to 我的, taps 退出登录 and confirms.
Future<void> signOutFromMine(WidgetTester tester, {bool settle = true}) async {
  await openTab(tester, '我的');
  final button = find.byKey(const Key('mine.signOut'));
  await tester.scrollUntilVisible(
    button,
    120,
    scrollable: find.descendant(
      of: find.byKey(const Key('mine.scroll')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('signOut.confirm')));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// The home greeting for [name] (split into wrap units, so match its label).
Finder greetingFor(String name) => find.byWidgetPredicate(
  // The greeting uses the surname + 同学, e.g. 张三 → 张同学.
  (w) =>
      w is Semantics &&
      (w.properties.label ?? '').endsWith('，${name.characters.first}同学'),
);

/// Types a room on the drawn keypad (clears what is there first).
Future<void> typeRoom(WidgetTester tester, String room) async {
  final back = find.byKey(const Key('room.key.back'));
  await tester.longPress(back);
  await tester.pump();
  for (final ch in room.split('')) {
    await tester.tap(find.byKey(Key('room.key.$ch')));
    await tester.pump();
  }
}
