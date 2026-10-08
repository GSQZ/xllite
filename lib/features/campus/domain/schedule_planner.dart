import 'academic_models.dart';
import 'campus_failure.dart';
import 'records.dart';
import 'json_fields.dart';

/// Campus wall clock, represented in UTC fields so calculations never depend
/// on the phone's timezone or daylight saving. Convert instants with campusNow.
DateTime campusNow(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 8));
DateTime _day(DateTime civil) =>
    DateTime.utc(civil.year, civil.month, civil.day);

class SectionTime {
  const SectionTime(
    this.section,
    this.startMinute,
    this.endMinute, {
    int? endSection,
  }) : endSection = endSection ?? section;
  final int section, startMinute, endMinute;
  final int endSection;
}

class CalendarDateOverride {
  const CalendarDateOverride({
    required this.date,
    required this.scheduleDate,
    required this.reason,
  });
  final DateTime date;
  final DateTime? scheduleDate;
  final String reason;
}

DateTime _calendarDate(Object? value) {
  final text = textValue(value, required: true);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) invalidData();
  final parts = text.split('-').map(int.parse).toList();
  final result = DateTime.utc(parts[0], parts[1], parts[2]);
  if (result.year != parts[0] ||
      result.month != parts[1] ||
      result.day != parts[2]) {
    invalidData();
  }
  return result;
}

int _calendarMinute(Object? value) {
  final text = textValue(value, required: true);
  if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(text)) invalidData();
  final parts = text.split(':').map(int.parse).toList();
  return parts[0] * 60 + parts[1];
}

class AcademicCalendar {
  AcademicCalendar({
    required this.term,
    required DateTime firstMonday,
    required this.weekCount,
    required List<SectionTime> sections,
    DateTime? classesStartOn,
    this.freshmanClassesStartOn,
    this.teachingWeekCount,
    this.sourceTitle = '',
    this.sourceUrl = '',
    this.notes = '',
    List<CalendarDateOverride> dateOverrides = const [],
  }) : firstMonday = _day(firstMonday),
       classesStartOn = _day(classesStartOn ?? firstMonday),
       dateOverrides = List.unmodifiable(dateOverrides),
       sections = List.unmodifiable(sections) {
    if (term.trim().isEmpty ||
        this.firstMonday.weekday != DateTime.monday ||
        weekCount < 1 ||
        weekCount > 60 ||
        (teachingWeekCount != null &&
            (teachingWeekCount! < 1 || teachingWeekCount! > weekCount)) ||
        this.classesStartOn.isBefore(this.firstMonday) ||
        !this.classesStartOn.isBefore(
          this.firstMonday.add(Duration(days: weekCount * 7)),
        ) ||
        sections.map((s) => s.section).toSet().length != sections.length ||
        sections.any(
          (s) =>
              s.section < 1 ||
              s.endSection < s.section ||
              s.endSection > 30 ||
              s.startMinute < 0 ||
              s.endMinute > 1440 ||
              s.endMinute <= s.startMinute,
        )) {
      invalidInput('校历或作息时间配置无效');
    }
    final sorted = [...sections]
      ..sort((a, b) => a.section.compareTo(b.section));
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].section <= sorted[i - 1].endSection ||
          sorted[i].startMinute < sorted[i - 1].endMinute) {
        invalidInput('作息节次时间重叠');
      }
    }
    final dates = <DateTime>{};
    for (final override in dateOverrides) {
      if (!dates.add(_day(override.date)) ||
          weekOn(override.date) == null ||
          (override.scheduleDate != null &&
              weekOn(override.scheduleDate!) == null)) {
        invalidInput('调课日期无效或重复');
      }
    }
  }
  final String term;
  final DateTime firstMonday;
  final int weekCount;
  final List<SectionTime> sections;
  final DateTime classesStartOn;
  final DateTime? freshmanClassesStartOn;
  final int? teachingWeekCount;
  final String sourceTitle, sourceUrl, notes;
  final List<CalendarDateOverride> dateOverrides;
  factory AcademicCalendar.fromJson(Json json) {
    if (json['timezone'] != 'Asia/Shanghai' || json['status'] != 'confirmed') {
      invalidData();
    }
    final source = objectValue(json['source']);
    return AcademicCalendar(
      term: textValue(json['term'], required: true),
      firstMonday: _calendarDate(json['firstMonday']),
      classesStartOn: _calendarDate(json['classesStartOn']),
      freshmanClassesStartOn: json['freshmanClassesStartOn'] == null
          ? null
          : _calendarDate(json['freshmanClassesStartOn']),
      weekCount: integerValue(json['weekCount']),
      teachingWeekCount: integerValue(json['teachingWeekCount']),
      sourceTitle: textValue(source['title']),
      sourceUrl: textValue(source['url']),
      notes: textValue(json['notes']),
      sections: listValue(
        json['sectionTimes'],
        (s) => SectionTime(
          integerValue(s['startSection']),
          _calendarMinute(s['startTime']),
          _calendarMinute(s['endTime']),
          endSection: integerValue(s['endSection']),
        ),
      ),
      dateOverrides: listValue(json['dateOverrides'], (d) {
        if (!d.containsKey('scheduleDate')) invalidData();
        return CalendarDateOverride(
          date: _calendarDate(d['date']),
          scheduleDate: d['scheduleDate'] == null
              ? null
              : _calendarDate(d['scheduleDate']),
          reason: textValue(d['reason'], required: true),
        );
      }),
    );
  }
  int? weekOn(DateTime civil) {
    final days = _day(civil).difference(firstMonday).inDays;
    if (days < 0 || days >= weekCount * 7) return null;
    return days ~/ 7 + 1;
  }
}

int? courseWeekday(String value) {
  final text = value.trim().replaceAll('星期', '').replaceAll('周', '');
  return const {
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '日': 7,
    '天': 7,
    '1': 1,
    '2': 2,
    '3': 3,
    '4': 4,
    '5': 5,
    '6': 6,
    '7': 7,
  }[text];
}

/// Unknown syntax returns null, never silently interprets it as 'no classes'.
Set<int>? parseSchoolNumbers(String value, {bool weeks = false}) {
  var text = value
      .trim()
      .replaceAll('，', ',')
      .replaceAll('、', ',')
      .replaceAll('；', ',')
      .replaceAll(';', ',')
      .replaceAll('－', '-')
      .replaceAll('—', '-')
      .replaceAll('至', '-')
      .replaceAll('～', '-')
      .replaceAll('(', '')
      .replaceAll(')', '')
      .replaceAll('（', '')
      .replaceAll('）', '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(weeks ? '周' : '节', '');
  if (text.isEmpty) return null;
  final result = <int>{};
  // A suffix after a range/list conventionally applies to the whole expression.
  String? globalParity;
  if (weeks && RegExp(r'^[\d,\-]+[单双]$').hasMatch(text)) {
    globalParity = text.substring(text.length - 1);
    text = text.substring(0, text.length - 1);
  }
  for (final part in text.split(',')) {
    // The school also enumerates sections as "07-08-09-10节".
    // Three or more numbers are an explicit list, not a range spanning gaps.
    if (!weeks && RegExp(r'^\d+(?:-\d+){2,}$').hasMatch(part)) {
      final numbers = part.split('-').map(int.tryParse).toList();
      var previous = 0;
      for (final number in numbers) {
        if (number == null || number <= previous || number > 30) return null;
        result.add(number);
        previous = number;
      }
      continue;
    }
    final match = RegExp(
      weeks ? r'^(\d+)(?:-(\d+))?([单双])?$' : r'^(\d+)(?:-(\d+))?$',
    ).firstMatch(part);
    if (match == null) return null;
    final start = int.tryParse(match[1]!);
    final end = int.tryParse(match[2] ?? match[1]!);
    if (start == null ||
        end == null ||
        start < 1 ||
        end < start ||
        end > (weeks ? 60 : 30)) {
      return null;
    }
    final parity = weeks ? match[3] ?? globalParity : null;
    for (var n = start; n <= end; n++) {
      if (parity == '单' && n.isEven || parity == '双' && n.isOdd) continue;
      result.add(n);
    }
  }
  return Set.unmodifiable(result);
}

class CourseOccurrence {
  const CourseOccurrence({
    required this.course,
    required this.startsAt,
    required this.endsAt,
  });
  final ScheduleCourse course;

  /// Actual UTC instants, unlike the calendar's civil date.
  final DateTime startsAt, endsAt;
  bool isOngoing(DateTime now) =>
      !now.isBefore(startsAt) && now.isBefore(endsAt);
}

enum DayScheduleStatus {
  needsCalendar,
  outsideTerm,
  incomplete,
  noClasses,
  upcoming,
  inClass,
  finished,
}

class DaySchedule {
  DaySchedule({
    required this.status,
    this.week,
    List<CourseOccurrence> courses = const [],
    List<ScheduleCourse> unresolved = const [],
    this.current,
    this.next,
  }) : courses = List.unmodifiable(courses),
       unresolved = List.unmodifiable(unresolved);
  final DayScheduleStatus status;
  final int? week;
  final List<CourseOccurrence> courses;
  final List<ScheduleCourse> unresolved;
  final CourseOccurrence? current, next;
}

class SchedulePlanner {
  const SchedulePlanner();
  DaySchedule today(
    Schedule schedule,
    AcademicCalendar? calendar,
    DateTime now,
  ) {
    if (calendar == null || calendar.term != schedule.term) {
      return DaySchedule(status: DayScheduleStatus.needsCalendar);
    }
    final civil = campusNow(now);
    final week = calendar.weekOn(civil);
    if (week == null) return DaySchedule(status: DayScheduleStatus.outsideTerm);
    final override = calendar.dateOverrides
        .where((d) => _day(d.date) == _day(civil))
        .firstOrNull;
    if (override != null && override.scheduleDate == null ||
        _day(civil).isBefore(calendar.classesStartOn)) {
      return DaySchedule(status: DayScheduleStatus.noClasses, week: week);
    }
    final scheduleDay = override?.scheduleDate ?? civil;
    final scheduleWeek = calendar.weekOn(scheduleDay)!;
    final result = <CourseOccurrence>[];
    final meetings = <(String, String, String, DateTime, DateTime)>{};
    final unresolved = <ScheduleCourse>[];
    final times = {
      for (final s in calendar.sections)
        for (var n = s.section; n <= s.endSection; n++) n: s,
    };
    for (final course in schedule.courses) {
      final weekday = courseWeekday(course.day);
      final weeks = parseSchoolNumbers(course.weeks, weeks: true);
      if (weekday != null && weekday != scheduleDay.weekday) continue;
      if (weeks != null && !weeks.contains(scheduleWeek)) continue;
      final sections = parseSchoolNumbers(course.sections);
      if (weekday == null ||
          weeks == null ||
          sections == null ||
          sections.isEmpty ||
          sections.any(
            (s) =>
                !times.containsKey(s) ||
                !{
                  for (
                    var n = times[s]!.section;
                    n <= times[s]!.endSection;
                    n++
                  )
                    n,
                }.every(sections.contains),
          )) {
        unresolved.add(course);
        continue;
      }
      final sorted = sections.toList()..sort();
      // A non-contiguous section list is multiple meetings, not one long class.
      var start = sorted.first;
      var end = start;
      void add() {
        final midnight = _day(civil).subtract(const Duration(hours: 8));
        final startsAt = midnight.add(
          Duration(minutes: times[start]!.startMinute),
        );
        final endsAt = midnight.add(Duration(minutes: times[end]!.endMinute));
        // A class spanning multiple table cells is repeated by the upstream
        // scraper with different slot labels. Keep one identical meeting;
        // different teachers, rooms, dates or times remain distinct.
        if (!meetings.add((
          course.title,
          course.teacher,
          course.location,
          startsAt,
          endsAt,
        ))) {
          return;
        }
        result.add(
          CourseOccurrence(course: course, startsAt: startsAt, endsAt: endsAt),
        );
      }

      for (final section in sorted.skip(1)) {
        if (section != end + 1) {
          add();
          start = section;
        }
        end = section;
      }
      add();
    }
    result.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    CourseOccurrence? current, next;
    for (final course in result) {
      if (course.isOngoing(now)) current ??= course;
      if (course.startsAt.isAfter(now)) next ??= course;
    }
    return DaySchedule(
      week: week,
      courses: result,
      unresolved: unresolved,
      current: current,
      next: next,
      status: unresolved.isNotEmpty
          ? DayScheduleStatus.incomplete
          : result.isEmpty
          ? DayScheduleStatus.noClasses
          : current != null
          ? DayScheduleStatus.inClass
          : next != null
          ? DayScheduleStatus.upcoming
          : DayScheduleStatus.finished,
    );
  }
}

class ExamOccurrence {
  const ExamOccurrence(this.exam, this.startsAt, this.endsAt);
  final Exam exam;
  final DateTime? startsAt, endsAt;
  factory ExamOccurrence.parse(Exam exam) {
    final match = RegExp(
      r'^(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})日?\s+(\d{1,2}):(\d{2})\s*[-~～—]\s*(\d{1,2}):(\d{2})$',
    ).firstMatch(exam.examTime.trim());
    if (match == null) return ExamOccurrence(exam, null, null);
    final values = [for (var i = 1; i <= 7; i++) int.parse(match[i]!)];
    final [year, month, day, sh, sm, eh, em] = values;
    final date = DateTime.utc(year, month, day);
    if (date.year != year ||
        date.month != month ||
        date.day != day ||
        sh > 23 ||
        eh > 23 ||
        sm > 59 ||
        em > 59 ||
        eh * 60 + em <= sh * 60 + sm) {
      return ExamOccurrence(exam, null, null);
    }
    return ExamOccurrence(
      exam,
      date.add(Duration(hours: sh - 8, minutes: sm)),
      date.add(Duration(hours: eh - 8, minutes: em)),
    );
  }
}
