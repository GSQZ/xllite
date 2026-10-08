import 'package:flutter/foundation.dart';

import '../../auth/auth.dart';
import '../domain/academic_models.dart';
import '../domain/campus_repository.dart';
import '../domain/campus_local_data.dart';
import '../domain/card_models.dart';
import '../domain/records.dart';
import 'campus_code_controller.dart';
import 'home_controller.dart';
import 'payment_controller.dart';
import 'resource_controller.dart';
import 'transactions_controller.dart';
import 'widget_bridge.dart';

/// App-owned business services. Construction never sends a request. Screens
/// subscribe to individual resources and load explicitly, outside build().
class CampusController {
  CampusController({
    required this.auth,
    required this.repository,
    this._onDispose,
  }) {
    home = HomeController(repository, profile: profile, exams: exams);
    widgetSource = CampusWidgetSource(this);
    transactions = TransactionsController(repository);
    payments = PaymentController(repository);
    campusCode = CampusCodeController(repository);
    _revision = auth.sessionRevision;
    _authenticated = auth.state.isAuthenticated;
    auth.addListener(_authChanged);
    _attachCache(profile);
    _attachCache(schedule);
    _attachCache(grades);
    _attachCache(exams);
    _attachCache(training);
    _attachCache(balance);
    _attachCache(electricity);
    _attachCache(home.schedule);
    balance.freshness = electricity.freshness = const Duration(seconds: 30);
  }
  void _attachCache<T>(ResourceController<T> resource) {
    final local = repository;
    if (local is CampusLocalData) {
      resource.readCache = (key) => (local as CampusLocalData).readCached<T>(
        resource.operation,
        key: key,
      );
    }
  }

  final AuthController auth;
  final CampusRepository repository;
  final VoidCallback? _onDispose;
  final profile = ResourceController<StudentProfile>('jw.profile');
  final schedule = ResourceController<Schedule>('jw.schedule');
  final grades = ResourceController<Grades>('jw.grades');
  final exams = ResourceController<List<Exam>>('jw.exams');
  final training = ResourceController<List<TrainingRecord>>('jw.training');
  final balance = ResourceController<List<CardAccount>>('newcard.balance');
  final electricity = ResourceController<ElectricityAccount>(
    'newcard.electricity.account',
  );
  late final HomeController home;

  /// The home-screen widget reads the timetable through this.
  late final CampusWidgetSource widgetSource;
  late final TransactionsController transactions;
  late final PaymentController payments;
  late final CampusCodeController campusCode;
  late int _revision;
  late bool _authenticated;
  bool _disposed = false;
  int _roomGeneration = 0;
  Future<void>? _restoringRoom;
  String? roomStorageError;

  Future<void> restorePreferences() => _restoringRoom ??= _restoreRoom();
  Future<void> _restoreRoom() async {
    final generation = _roomGeneration;
    final revision = auth.sessionRevision;
    try {
      final local = repository;
      final room = local is CampusLocalData
          ? await (local as CampusLocalData).readPreference('room')
          : null;
      if (_disposed ||
          revision != auth.sessionRevision ||
          generation != _roomGeneration) {
        return;
      }
      if (room != null && room.trim().isNotEmpty && _room == null) {
        await loadElectricity(room);
      }
    } catch (_) {
      /* A missing preference does not block home loading. */
    }
  }

  Future<void> clearCache() async {
    final local = repository;
    if (local is CampusLocalData) await (local as CampusLocalData).clearCache();
    home.resetSession();
    for (final resource in [
      profile,
      schedule,
      grades,
      exams,
      training,
      balance,
      electricity,
    ]) {
      resource.reset();
    }
    transactions.reset();
  }

  String? _term;
  String? get selectedTerm => _term;
  String? _gradeTerm;
  GradeMode _gradeMode = GradeMode.bestByCourse;
  String? _room;
  String? get roomQuery => _room;
  String? get gradeTerm => _gradeTerm;
  GradeMode get gradeMode => _gradeMode;

  Future<void> loadProfile({bool refresh = false}) =>
      profile.load(repository.profile, refresh: refresh);
  Future<void> loadSchedule({String? term, bool refresh = false}) {
    _term = term == null || term.trim().isEmpty ? null : term.trim();
    final selected = _term;
    if (selected == null && !refresh) schedule.seed(home.schedule.state);
    return schedule.load(
      () => repository.schedule(term: selected),
      key: selected,
      refresh: refresh,
    );
  }

  Future<void> loadGrades({
    String? term,
    GradeMode mode = GradeMode.bestByCourse,
    bool refresh = false,
  }) {
    _gradeTerm = term == null || term.trim().isEmpty ? null : term.trim();
    _gradeMode = mode;
    final selected = _gradeTerm;
    return grades.load(
      () => repository.grades(term: selected, mode: mode),
      key: (selected, mode),
      refresh: refresh,
    );
  }

  Future<void> loadExams({bool refresh = false}) =>
      exams.load(repository.exams, refresh: refresh);
  Future<void> loadTraining({bool refresh = false}) =>
      training.load(repository.training, refresh: refresh);
  Future<void> loadBalance({bool refresh = false}) =>
      balance.load(repository.balance, refresh: refresh);
  Future<void> loadElectricity(String room, {bool refresh = false}) async {
    final generation = ++_roomGeneration;
    final revision = auth.sessionRevision;
    _room = room.trim();
    final selected = _room!;
    await electricity.load(
      () => repository.electricity(selected),
      key: selected,
      refresh: refresh,
    );
    if (_disposed ||
        generation != _roomGeneration ||
        revision != auth.sessionRevision ||
        electricity.state.phase != ResourcePhase.ready) {
      return;
    }
    try {
      final local = repository;
      if (local is CampusLocalData) {
        await (local as CampusLocalData).writePreference('room', selected);
      }
      roomStorageError = null;
    } catch (_) {
      roomStorageError = '电量已查询，但宿舍未能保存，请稍后重试';
    }
  }

  void _authChanged() {
    if (_disposed) return;
    if (_revision == auth.sessionRevision &&
        _authenticated == auth.state.isAuthenticated) {
      return;
    }
    _revision = auth.sessionRevision;
    _authenticated = auth.state.isAuthenticated;
    _term = _gradeTerm = _room = null;
    _roomGeneration++;
    _restoringRoom = null;
    roomStorageError = null;
    _gradeMode = GradeMode.bestByCourse;
    home.resetSession();
    for (final resource in [
      profile,
      schedule,
      grades,
      exams,
      training,
      balance,
      electricity,
    ]) {
      resource.reset();
    }
    transactions.reset();
    payments.resetSession();
    campusCode.resetSession();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    auth.removeListener(_authChanged);
    widgetSource.dispose();
    home.dispose();
    for (final resource in [
      profile,
      schedule,
      grades,
      exams,
      training,
      balance,
      electricity,
    ]) {
      resource.dispose();
    }
    transactions.dispose();
    payments.dispose();
    campusCode.dispose();
    _onDispose?.call();
  }
}
