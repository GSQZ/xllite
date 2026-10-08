import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/academic_models.dart';
import '../domain/campus_repository.dart';
import '../domain/records.dart';
import '../domain/schedule_planner.dart';
import 'resource_controller.dart';

class HomeSnapshot {
  HomeSnapshot({
    required this.profile,
    required this.schedule,
    required this.exams,
    required this.now,
    required this.day,
    required List<ExamOccurrence> upcomingExams,
    required List<Exam> undatedExams,
  }) : upcomingExams = List.unmodifiable(upcomingExams),
       undatedExams = List.unmodifiable(undatedExams);
  final ResourceState<StudentProfile> profile;
  final ResourceState<Schedule> schedule;
  final ResourceState<List<Exam>> exams;
  final DateTime now;

  /// Null means schedule not available. needsCalendar means data exists but
  /// exact timing cannot be computed. Neither means 'today has no classes'.
  final DaySchedule? day;
  final List<ExamOccurrence> upcomingExams;
  final List<Exam> undatedExams;
}

class HomeController extends ChangeNotifier {
  HomeController(
    this.repository, {
    required this.profile,
    required this.exams,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    profile.addListener(_changed);
    exams.addListener(_changed);
    schedule.addListener(_changed);
  }
  final CampusRepository repository;
  final ResourceController<StudentProfile> profile;
  final ResourceController<List<Exam>> exams;

  /// Separate from the timetable screen's selected term, so browsing history
  /// never changes today's card.
  final schedule = ResourceController<Schedule>('jw.schedule');
  final DateTime Function() _now;
  AcademicCalendar? _calendar;
  AcademicCalendar? get calendar => schedule.state.data?.calendar ?? _calendar;
  bool _disposed = false;
  Timer? _clock;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void configureCalendar(AcademicCalendar? calendar) {
    if (_disposed) return;
    _calendar = calendar;
    notifyListeners();
  }

  HomeSnapshot get state {
    final now = _now();
    final upcoming = <ExamOccurrence>[];
    final undated = <Exam>[];
    for (final exam in exams.state.data ?? <Exam>[]) {
      final occurrence = ExamOccurrence.parse(exam);
      if (occurrence.endsAt == null) {
        undated.add(exam);
      } else if (occurrence.endsAt!.isAfter(now)) {
        upcoming.add(occurrence);
      }
    }
    upcoming.sort((a, b) => a.startsAt!.compareTo(b.startsAt!));
    final data = schedule.state.data;
    return HomeSnapshot(
      profile: profile.state,
      schedule: schedule.state,
      exams: exams.state,
      now: now,
      day: data == null
          ? null
          : const SchedulePlanner().today(data, calendar, now),
      upcomingExams: upcoming,
      undatedExams: undated,
    );
  }

  Future<void> load({bool refresh = false}) async {
    if (_disposed) return;
    await Future.wait([
      profile.load(repository.profile, refresh: refresh),
      schedule.load(() => repository.schedule(), refresh: refresh),
      exams.load(repository.exams, refresh: refresh),
    ]);
  }

  /// Active only while the home page is both visible and in the foreground.
  /// The clock updates derived dates/countdowns without polling school APIs.
  void setActive(bool active) {
    if (_disposed) return;
    _clock?.cancel();
    if (active) {
      notifyListeners();
      _clock = Timer.periodic(
        const Duration(minutes: 1),
        (_) => notifyListeners(),
      );
    }
  }

  void resetSession() {
    if (_disposed) return;
    _clock?.cancel();
    _calendar = null;
    schedule.reset();
  }

  @override
  void dispose() {
    _disposed = true;
    _clock?.cancel();
    profile.removeListener(_changed);
    exams.removeListener(_changed);
    schedule.removeListener(_changed);
    schedule.dispose();
    super.dispose();
  }
}
