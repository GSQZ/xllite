import 'dart:async';

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

/// Owns the test session outside the tab, so leaving Mine never cancels it.
/// Production scheduling stays gated until a background end transport exists.
class CourseActivityController extends ChangeNotifier {
  CourseActivityController({
    required this.auth,
    required this.source,
    this.host = const PlatformCourseActivityHost(),
    bool? supportedPlatform,
  }) : supportedPlatform =
           supportedPlatform ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    auth.addListener(_authChanged);
    source.addListener(_sourceChanged);
    _authChanged();
  }

  static const testerUsername = '202303310112';
  final AuthController auth;
  final WidgetScheduleSource source;
  final CourseActivityHost host;
  final bool supportedPlatform;
  bool get canTest =>
      supportedPlatform &&
      auth.state.isAuthenticated &&
      auth.state.session?.username == testerUsername;
  bool testing = false;
  bool busy = false;
  String? error;
  String phase = '';
  int accent = 0xFF1D6FD8;
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
      now: DateTime.now(),
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
    final account = auth.state.isAuthenticated
        ? auth.state.session?.username
        : null;
    if (_revision == auth.sessionRevision && _account == account) return;
    final generation = ++_generation;
    _revision = auth.sessionRevision;
    _account = account;
    testing = busy = false;
    phase = '';
    error = null;
    _poll?.cancel();
    if (supportedPlatform) {
      unawaited(
        _serial(() async {
          try {
            final state = await host.invoke('session', {'username': account});
            if (!_disposed && generation == _generation) _accept(state);
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

  void _sourceChanged() => _notify();

  void _accept(Map<String, dynamic> state) {
    testing = state['testing'] == true;
    phase = state['phase'] as String? ?? '';
    _poll?.cancel();
    if (testing && _foreground) {
      _poll = Timer(const Duration(seconds: 2), refresh);
    }
    _notify();
  }

  Future<void> setTesting(bool value) async {
    if (_disposed || busy || !canTest) return;
    busy = true;
    error = null;
    _notify();
    final generation = _generation;
    final next = plan.firstOrNull;
    try {
      await _serial(() async {
        // Authorization is checked again after any earlier channel operation.
        if (_disposed || generation != _generation || !canTest) return;
        final state = await host.invoke(value ? 'startTest' : 'stopTest', {
          'accent': accent,
          if (next != null) 'course': next.toJson(),
        });
        if (!_disposed && generation == _generation) _accept(state);
      });
    } on PlatformException catch (failure) {
      if (generation == _generation) error = failure.message ?? '灵动岛启动失败，请重试';
    } catch (_) {
      if (generation == _generation) error = '灵动岛服务不可用，请重新打开 App';
    } finally {
      if (!_disposed && generation == _generation) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> refresh() async {
    if (_disposed || !canTest || !_foreground) return;
    final generation = _generation;
    await _serial(() async {
      if (_disposed || generation != _generation) return;
      try {
        final state = await host.invoke('status', {});
        if (!_disposed && generation == _generation) _accept(state);
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
