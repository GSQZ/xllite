import 'json_fields.dart';
import 'records.dart';
import 'schedule_planner.dart';
import 'campus_failure.dart';

enum GradeMode {
  bestByCourse('best_by_course'),
  raw('raw');

  const GradeMode(this.wireName);
  final String wireName;
}

class Schedule {
  Schedule({
    required this.term,
    required List<ScheduleCourse> courses,
    this.calendar,
    this.calendarStatus = 'unconfigured',
    this.termLabel = '',
  }) : courses = List.unmodifiable(courses);
  final String term;
  final List<ScheduleCourse> courses;
  final AcademicCalendar? calendar;
  final String calendarStatus, termLabel;
  factory Schedule.fromJson(Json json) {
    final term = textValue(json['term'], required: true);
    AcademicCalendar? calendar;
    var status = textValue(json['calendarStatus']);
    if (status.isEmpty) status = 'unconfigured';
    if (status == 'confirmed') {
      try {
        calendar = AcademicCalendar.fromJson(objectValue(json['calendar']));
        if (calendar.term != term) invalidData();
      } catch (_) {
        calendar = null;
        status = 'unavailable';
      }
    }
    return Schedule(
      term: term,
      courses: listValue(json['courses'], ScheduleCourse.fromJson),
      termLabel: textValue(json['termLabel']),
      calendar: calendar,
      calendarStatus: status,
    );
  }
}

class GradeSummary {
  const GradeSummary({
    required this.courseCount,
    required this.totalCredits,
    required this.gpaCredits,
    required this.weightedGradePoint,
    required this.failedCourseCount,
    required this.failedCredits,
    this.term = '',
  });
  final int courseCount, failedCourseCount;
  final double totalCredits, gpaCredits, failedCredits;

  /// Backend may return null when no course participates in GPA calculation.
  final double? weightedGradePoint;
  final String term;
  factory GradeSummary.fromJson(Json json) => GradeSummary(
    courseCount: integerValue(json['courseCount']),
    totalCredits: numberValue(json['totalCredits']),
    gpaCredits: numberValue(json['gpaCredits']),
    weightedGradePoint: json['weightedGradePoint'] == null
        ? null
        : numberValue(json['weightedGradePoint']),
    failedCourseCount: integerValue(json['failedCourseCount']),
    failedCredits: numberValue(json['failedCredits']),
    term: textValue(json['term']),
  );
}

class GradeSourceSummary {
  const GradeSourceSummary(
    this.gradeListCount,
    this.graduationAuditCount,
    this.addedFromGraduationAuditCount,
  );
  final int gradeListCount, graduationAuditCount, addedFromGraduationAuditCount;
  factory GradeSourceSummary.fromJson(Json json) => GradeSourceSummary(
    integerValue(json['gradeListCount']),
    integerValue(json['graduationAuditCount']),
    integerValue(json['addedFromGraduationAuditCount']),
  );
}

class Grades {
  Grades.fromJson(Json json)
    : mode = textValue(json['mode'], required: true),
      summary = GradeSummary.fromJson(objectValue(json['summary'])),
      rawSummary = GradeSummary.fromJson(objectValue(json['rawSummary'])),
      terms = listValue(json['terms'], GradeSummary.fromJson),
      normalGrades = listValue(json['normalGrades'], Grade.fromJson),
      makeupGrades = listValue(json['makeupGrades'], Grade.fromJson),
      failedCourses = listValue(json['failedCourses'], Grade.fromJson),
      sourceSummary = GradeSourceSummary.fromJson(
        objectValue(json['sourceSummary']),
      );
  final String mode;
  final GradeSummary summary, rawSummary;
  final List<GradeSummary> terms;
  final List<Grade> normalGrades, makeupGrades, failedCourses;
  final GradeSourceSummary sourceSummary;
}
