import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../auth/auth.dart';
import 'campus_controller.dart';
import '../domain/academic_models.dart';
import '../domain/schedule_planner.dart';
import '../domain/widget_snapshot.dart';

/// Sends the snapshot to the home-screen widget.
///
/// Implementations must never throw: a platform without the widget, a
/// denied channel or a signed-out device simply does nothing.
abstract interface class WidgetHost {
  Future<void> sync(Map<String, Object?> snapshot);
  Future<void> clear();
}

/// The real host: one method channel, one JSON document.
class PlatformWidgetHost implements WidgetHost {
  const PlatformWidgetHost({
    this.channel = const MethodChannel('xinli_lite/widgets'),
    this.appGroup = 'group.com.sayqz.xinliLite',
  });

  final MethodChannel channel;

  /// The App Group the iOS widget reads the snapshot from. Android ignores it.
  final String appGroup;

  @override
  Future<void> sync(Map<String, Object?> snapshot) async {
    try {
      await channel.invokeMethod<void>('sync', {
        'raw': jsonEncode(snapshot),
        'group': appGroup,
      });
    } on Object {
      /* The widget is optional; never interrupt the app for it. */
    }
  }

  @override
  Future<void> clear() async {
    try {
      await channel.invokeMethod<void>('clear');
    } on Object {
      /* Ignored, as above. */
    }
  }
}

/// A host that keeps what it was given, for tests and previews.
class MemoryWidgetHost implements WidgetHost {
  final List<Map<String, Object?>> synced = [];
  int cleared = 0;

  @override
  Future<void> sync(Map<String, Object?> snapshot) async =>
      synced.add(snapshot);

  @override
  Future<void> clear() async => cleared++;
}

/// Where the bridge reads the timetable from. The app implements this
/// with [CampusController]; tests use a plain in-memory source.
abstract interface class WidgetScheduleSource implements Listenable {
  Schedule? get widgetSchedule;
  AcademicCalendar? get widgetCalendar;
}

/// [WidgetScheduleSource] backed by the app's own controller. It listens to
/// the home tab's current term; browsing historical terms must not affect it.
class CampusWidgetSource extends ChangeNotifier
    implements WidgetScheduleSource {
  CampusWidgetSource(this._campus) {
    _campus.home.schedule.addListener(notifyListeners);
  }

  final CampusController _campus;
  bool _disposed = false;

  @override
  Schedule? get widgetSchedule => _campus.home.schedule.state.data;

  @override
  AcademicCalendar? get widgetCalendar => _campus.home.calendar;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _campus.home.schedule.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Keeps the home-screen widget in step with the app.
///
/// It listens to the schedule resource and to sign-in, rebuilds the snapshot
/// whenever either changes, and also once a minute so a widget opened later
/// in the day still shows the right class. Pushing is silent: the widget is
/// a convenience, never a reason for the app to fail or to wait.
class WidgetBridge {
  WidgetBridge({
    required this.auth,
    required this.source,
    required this.host,
    DateTime Function()? now,
    Duration? tick,
  }) : _now = now ?? DateTime.now,
       _tick = tick ?? const Duration(minutes: 1);

  final AuthController auth;
  final WidgetScheduleSource source;
  final WidgetHost host;
  final DateTime Function() _now;

  /// How often to rebuild while the app is in the foreground: a class
  /// starting or ending should reach the widget within a minute.
  final Duration _tick;

  Timer? _timer;
  bool _started = false;
  bool _dirty = false;
  String? _lastJson;
  Future<void> _writes = Future.value();
  int _revision = 0;
  int _accent = 0xFF1D6FD8;

  /// The skin colour the widget should use.
  set accent(int value) {
    if (_accent == value) return;
    _accent = value;
    push();
  }

  void start() {
    if (_started || kIsWeb) return;
    _started = true;
    source.addListener(_changed);
    auth.addListener(_authChanged);
    _timer = Timer.periodic(_tick, (_) => push());
    if (auth.state.isAuthenticated) push();
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    source.removeListener(_changed);
    auth.removeListener(_authChanged);
    _timer?.cancel();
    _timer = null;
  }

  void _changed() {
    _dirty = true;
    push();
  }

  /// Signing out must take the timetable off the home screen.
  void _authChanged() {
    if (auth.state.isAuthenticated) {
      _changed();
    } else {
      clear();
    }
  }

  /// Rebuilds and sends the snapshot; identical payloads are not re-sent.
  Future<void> push() async {
    if (!_started) return;
    if (!auth.state.isAuthenticated) return clear();
    // During startup retain the saved timeline until the current term loads.
    if (source.widgetSchedule == null) return;
    final snapshot = WidgetSnapshotBuilder(accent: _accent).timeline(
      schedule: source.widgetSchedule,
      calendar: source.widgetCalendar,
      now: _now(),
    );
    final json = jsonEncode(snapshot);
    if (json == _lastJson && !_dirty) return;
    _dirty = false;
    _lastJson = json;
    final revision = _revision;
    _writes = _writes.catchError((Object _) {}).then((_) async {
      if (_started && revision == _revision && auth.state.isAuthenticated) {
        await host.sync(snapshot);
      }
    });
    await _writes;
  }

  /// Serialize clearing after outstanding writes so sign-out cannot resurrect
  /// a previous account's timetable.
  Future<void> clear() async {
    _revision++;
    _lastJson = null;
    _dirty = false;
    _writes = _writes.catchError((Object _) {}).then((_) => host.clear());
    await _writes;
  }
}
