import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../auth/auth.dart';
import '../domain/course_reminder_plan.dart';
import 'widget_bridge.dart';

abstract interface class CourseActivityHost {
  Future<Map<String, dynamic>> invoke(String method, Map<String, Object?> args);
}

class PlatformCourseActivityHost implements CourseActivityHost {
  const PlatformCourseActivityHost();
  static const _channel = MethodChannel('xinli_lite/course_activities');

  @override
  Future<Map<String, dynamic>> invoke(
    String method,
    Map<String, Object?> args,
  ) async =>
      await _channel.invokeMapMethod<String, dynamic>(method, args) ?? {};
}

/// Account-scoped course reminders and native Live Activities.
/// Native scheduling survives suspension; timers here only refresh foreground UI.
class CourseActivityController extends ChangeNotifier {
  CourseActivityController({
    required this.auth,
    required this.source,
    this.host = const PlatformCourseActivityHost(),
    DateTime Function()? now,
    bool? supportedPlatform,
  }) : _now = now ?? DateTime.now,
       supportedPlatform =
           supportedPlatform ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    auth.addListener(_authChanged);
    source.addListener(_sourceChanged);
    _authChanged();
  }

  final AuthController auth;
  final WidgetScheduleSource source;
  final CourseActivityHost host;
  final bool supportedPlatform;
  final DateTime Function() _now;
  static const apiOrigin = String.fromEnvironment(
    'XJIT_API_BASE_URL',
    defaultValue: 'https://xllite.sayqz.com',
  );
  bool enabled = false;
  bool liveActivities = false;
  bool scheduledSupported = false;
  bool activitiesAllowed = false;
  String notificationPermission = 'notDetermined';
  int scheduledCount = 0;
  int liveCount = 0;
  DateTime? scheduledUntil;
  DateTime? lastSyncedAt;
  String? schedulingWarning;
  String? _lastPlan;
  bool _sessionReady = false;
  bool get ready => _sessionReady;
  bool get hasCalendar =>
      source.widgetSchedule != null &&
      source.widgetCalendar != null &&
      source.widgetCalendar!.term == source.widgetSchedule!.term;
  bool _syncQueued = false;
  int _accent = 0xFF1D6FD8;
  int get accent => _accent;
  set accent(int value) {
    if (_accent == value) return;
    _accent = value;
    _sourceChanged();
  }

  bool busy = false;
  String? error;
  bool _disposed = false;
  bool _foreground = true;
  int _generation = 0;
  int? _revision;
  String? _account;
  Timer? _poll;
  Future<void> _queue = Future.value();

  List<CourseReminder> get plan {
    final schedule = source.widgetSchedule;
    if (schedule == null || !auth.state.isAuthenticated) return const [];
    return const CourseReminderPlanner().build(
      schedule: schedule,
      calendar: source.widgetCalendar,
      now: _now(),
    );
  }

  Future<void> _serial(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.catchError((Object _) {});
    return next;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _authChanged() {
    // Startup recovery must not erase an already registered native queue.
    if (auth.state.phase == AuthPhase.idle ||
        auth.state.phase == AuthPhase.restoring) {
      return;
    }
    final account = auth.state.isAuthenticated
        ? auth.state.session?.username
        : null;
    if (_revision == auth.sessionRevision && _account == account) return;
    final generation = ++_generation;
    _revision = auth.sessionRevision;
    _account = account;
    busy = false;
    error = null;
    _lastPlan = null;
    _sessionReady = false;
    enabled = liveActivities = false;
    scheduledCount = liveCount = 0;
    scheduledUntil = lastSyncedAt = null;
    schedulingWarning = null;
    _poll?.cancel();
    if (supportedPlatform) {
      unawaited(
        _serial(() async {
          try {
            final state = await host.invoke('session', {
              'username': account,
              'origin': apiOrigin,
            });
            if (!_disposed && generation == _generation) {
              _sessionReady = true;
              _accept(state);
              _sourceChanged();
            }
          } catch (_) {
            if (!_disposed && generation == _generation && account != null) {
              error = '无法连接灵动岛服务，请重新打开 App';
              _notify();
            }
          }
        }),
      );
    }
    _notify();
  }

  void _sourceChanged() {
    _notify();
    if (_disposed ||
        !_foreground ||
        !_sessionReady ||
        !supportedPlatform ||
        !enabled ||
        !auth.state.isAuthenticated ||
        _syncQueued) {
      return;
    }
    // Coalesce loading/content notifications and read the latest data inside
    // the serial queue, never a snapshot belonging to a previous account.
    _syncQueued = true;
    unawaited(
      _serial(() async {
        _syncQueued = false;
        if (_disposed || !_sessionReady || !_foreground || !enabled) return;
        await _syncPlan();
      }),
    );
  }

  Future<void> _syncPlan({bool force = false}) async {
    final schedule = source.widgetSchedule;
    final calendar = source.widgetCalendar;
    if (schedule == null ||
        calendar == null ||
        calendar.term != schedule.term ||
        !auth.state.isAuthenticated) {
      return;
    }
    final generation = _generation;
    final courses = plan.map((e) => e.toJson()).toList();
    final fingerprint = jsonEncode([_account, accent, courses]);
    if (!force && fingerprint == _lastPlan) return;
    try {
      final state = await host.invoke('sync', {
        'courses': courses,
        'accent': accent,
      });
      if (!_disposed && generation == _generation) {
        _lastPlan = fingerprint;
        error = null;
        _accept(state);
      }
    } on PlatformException catch (failure) {
      if (generation == _generation) error = failure.message ?? '课前提醒未能更新，请重试';
    } catch (_) {
      if (generation == _generation) error = '课前提醒未能更新，请重试';
    }
    _notify();
  }

  void _accept(Map<String, dynamic> state) {
    enabled = state['enabled'] == true;
    liveActivities = state['liveActivities'] == true;
    scheduledSupported = state['scheduledSupported'] == true;
    activitiesAllowed = state['activitiesAllowed'] == true;
    notificationPermission =
        state['notificationPermission'] as String? ?? 'notDetermined';
    scheduledCount = (state['scheduledCount'] as num?)?.toInt() ?? 0;
    liveCount = (state['liveCount'] as num?)?.toInt() ?? 0;
    DateTime? date(String key) => state[key] is num
        ? DateTime.fromMillisecondsSinceEpoch((state[key] as num).toInt())
        : null;
    scheduledUntil = date('scheduledUntil');
    lastSyncedAt = date('lastSyncedAt');
    schedulingWarning = state['warning'] as String?;
    _poll?.cancel();
    if (enabled && _foreground) {
      _poll = Timer(const Duration(minutes: 1), refresh);
    }
    _notify();
  }

  Future<void> configure({bool? reminders, bool? island}) async {
    if (_disposed ||
        busy ||
        !_sessionReady ||
        !supportedPlatform ||
        !auth.state.isAuthenticated) {
      return;
    }
    busy = true;
    error = null;
    _notify();
    final generation = _generation;
    await _serial(() async {
      if (_disposed || generation != _generation) return;
      try {
        final state = await host.invoke('configure', {
          'enabled': reminders ?? enabled,
          'liveActivities': island ?? liveActivities,
          'requestPermission': reminders == true,
        });
        if (!_disposed && generation == _generation) {
          _lastPlan = null;
          _accept(state);
          if (enabled) await _syncPlan(force: true);
        }
      } on PlatformException catch (failure) {
        if (generation == _generation) {
          error = failure.message ?? '提醒设置未能保存，请重试';
        }
      } catch (_) {
        if (generation == _generation) error = '提醒设置未能保存，请重试';
      }
    });
    if (!_disposed && generation == _generation) {
      busy = false;
      _notify();
    }
  }

  Future<void> openSettings() async {
    try {
      await host.invoke('openSettings', {});
    } catch (_) {
      error = '无法打开系统设置，请从设置中找到新理Lite';
      _notify();
    }
  }

  Future<void> refresh() async {
    if (_disposed || !supportedPlatform || !_sessionReady || !_foreground) {
      return;
    }
    final generation = _generation;
    await _serial(() async {
      if (_disposed || generation != _generation) return;
      try {
        final state = await host.invoke('status', {});
        if (!_disposed && generation == _generation) {
          _accept(state);
          if (enabled) await _syncPlan(force: true);
        }
      } catch (_) {
        if (!_disposed && generation == _generation) {
          error = '无法读取灵动岛状态，请重新打开 App';
          _notify();
        }
      }
    });
  }

  void setForeground(bool value) {
    _foreground = value;
    _poll?.cancel();
    if (value) unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _poll?.cancel();
    auth.removeListener(_authChanged);
    source.removeListener(_sourceChanged);
    super.dispose();
  }
}
