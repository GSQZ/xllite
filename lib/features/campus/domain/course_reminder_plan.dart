import 'dart:convert';

import 'academic_models.dart';
import 'schedule_planner.dart';
import 'widget_snapshot.dart';

/// Absolute instants; the native renderer does not interpret school formats.
class CourseReminder {
  const CourseReminder({
    required this.id,
    required this.title,
    required this.location,
    required this.teacher,
    required this.startsAt,
    required this.endsAt,
  });

  final String id, title, location, teacher;
  final DateTime startsAt, endsAt;
  DateTime get showAt => startsAt.subtract(const Duration(minutes: 15));
  DateTime get dismissAt => startsAt.add(const Duration(minutes: 1));

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'location': location,
    'teacher': teacher,
    'showAt': showAt.millisecondsSinceEpoch,
    'startsAt': startsAt.millisecondsSinceEpoch,
    'endsAt': endsAt.millisecondsSinceEpoch,
    'dismissAt': dismissAt.millisecondsSinceEpoch,
  };
}

/// Uses the same validated weeks, holiday overrides and UTC+8 clock as home.
/// A 7–10 section meeting produces TWO major-block reminders (7–8, 9–10).
class CourseReminderPlanner {
  const CourseReminderPlanner();

  List<CourseReminder> build({
    required Schedule schedule,
    required AcademicCalendar? calendar,
    required DateTime now,
    int days = 7,
  }) {
    if (calendar == null || calendar.term != schedule.term) return const [];
    final civil = campusNow(now);
    final midnight = DateTime.utc(
      civil.year,
      civil.month,
      civil.day,
    ).subtract(const Duration(hours: 8));
    final meetings = <String, CourseReminder>{};
    for (var offset = 0; offset < days; offset++) {
      final day = midnight.add(Duration(days: offset));
      final occurrences = const SchedulePlanner()
          .today(schedule, calendar, day)
          .courses;
      for (final occurrence in occurrences) {
        // A calendar can describe individual sections or a complete pair.
        // Never invent intermediate times inside an aggregate calendar entry.
        final blocks = <int, List<SectionTime>>{};
        for (final section in calendar.sections) {
          if ((section.section - 1) ~/ 2 != (section.endSection - 1) ~/ 2) {
            continue;
          }
          final start = day.add(Duration(minutes: section.startMinute));
          final end = day.add(Duration(minutes: section.endMinute));
          if (start.isBefore(occurrence.startsAt) ||
              end.isAfter(occurrence.endsAt)) {
            continue;
          }
          blocks.putIfAbsent((section.section - 1) ~/ 2, () => []).add(section);
        }
        for (final parts in blocks.values) {
          parts.sort((a, b) => a.section.compareTo(b.section));
          final start = day.add(Duration(minutes: parts.first.startMinute));
          if (!start.add(const Duration(minutes: 1)).isAfter(now)) continue;
          final end = day.add(Duration(minutes: parts.last.endMinute));
          final course = occurrence.course;
          final title = course.title.trim();
          final location = WidgetSnapshotBuilder.widgetWhere(course.location);
          final teacher = course.teacher.trim();
          // Canonical JSON, not hashCode (which isn't a persistent identifier).
          final id = jsonEncode([
            schedule.term,
            start.millisecondsSinceEpoch,
            end.millisecondsSinceEpoch,
            title,
            location,
            teacher,
          ]);
          meetings[id] = CourseReminder(
            id: id,
            title: title,
            location: location,
            teacher: teacher,
            startsAt: start,
            endsAt: end,
          );
        }
      }
    }
    final result = meetings.values.toList()
      ..sort((a, b) {
        final byTime = a.startsAt.compareTo(b.startsAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    return List.unmodifiable(result);
  }
}
