import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/campus/application/course_activity_controller.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../support/fakes.dart';
import 'course_reminder_test.dart' as fixture;

class ReminderHost implements CourseActivityHost {
  bool enabled = false;
  bool island = false;
  bool deny = false;
  final calls = <({String method, Map<String, Object?> args})>[];
  Completer<Map<String, dynamic>>? syncResponse;
  Map<String, dynamic> get state => {
    'enabled': enabled,
    'liveActivities': island,
    'scheduledSupported': true,
    'activitiesAllowed': true,
    'notificationPermission': deny ? 'denied' : 'authorized',
    'warning': deny ? '请开启通知' : null,
  };

  @override
  Future<Map<String, dynamic>> invoke(
    String method,
    Map<String, Object?> args,
  ) async {
    calls.add((method: method, args: args));
    if (method == 'session' && args['username'] == null) enabled = false;
    if (method == 'configure') {
      enabled = args['enabled'] == true;
      island = args['liveActivities'] == true;
    }
    if (method == 'sync' && syncResponse != null) return syncResponse!.future;
    return state;
  }
}

Future<void> settleQueue() => Future<void>.delayed(Duration.zero);

void main() {
  late AuthController auth;
  late fixture.Source source;
  late ReminderHost host;
  late CourseActivityController controller;

  setUp(() async {
    auth = AuthController(
      repository: FakeAuthRepository(stored: testSession()),
    );
    source = fixture.Source();
    host = ReminderHost();
    controller = CourseActivityController(
      auth: auth,
      source: source,
      host: host,
      supportedPlatform: true,
      now: () => DateTime.utc(2026, 10, 5),
    );
    await auth.restore();
    await settleQueue();
  });
  tearDown(() {
    controller.dispose();
    source.dispose();
    auth.dispose();
  });

  test(
    'ordinary accounts opt in; permission is requested only from explicit enable',
    () async {
      expect(host.calls.map((c) => c.method), ['session']);
      await controller.configure(reminders: true);
      expect(controller.enabled, isTrue);
      expect(
        host.calls
            .firstWhere((c) => c.method == 'configure')
            .args['requestPermission'],
        isTrue,
      );
      final courses = host.calls.last.args['courses'] as List;
      expect(courses, hasLength(2));
      expect(
        (courses.first as Map)['showAt'],
        DateTime.utc(2026, 10, 5, 9, 45).millisecondsSinceEpoch,
      );
      await controller.configure(island: true);
      expect(controller.liveActivities, isTrue);
      expect(
        host.calls
            .where((c) => c.method == 'configure')
            .last
            .args['requestPermission'],
        isFalse,
      );
    },
  );

  test(
    'coalesces identical data, updates themes and reconciles empty current term',
    () async {
      await controller.configure(reminders: true);
      final before = host.calls.where((c) => c.method == 'sync').length;
      source.notifyListeners();
      source.notifyListeners();
      await settleQueue();
      expect(host.calls.where((c) => c.method == 'sync'), hasLength(before));
      controller.accent = 0xFF009966;
      await settleQueue();
      expect(host.calls.last.args['accent'], 0xFF009966);
      source.widgetSchedule = Schedule(
        term: source.widgetCalendar!.term,
        courses: const [],
      );
      source.notifyListeners();
      await settleQueue();
      expect(host.calls.last.args['courses'], isEmpty);
    },
  );

  test(
    'missing calendar preserves native queue instead of clearing it',
    () async {
      await controller.configure(reminders: true);
      final before = host.calls.length;
      source.widgetCalendar = null;
      source.notifyListeners();
      await settleQueue();
      expect(host.calls, hasLength(before));
    },
  );

  test(
    'in-flight scheduling cannot restore another account after logout',
    () async {
      await controller.configure(reminders: true);
      host.syncResponse = Completer();
      controller.accent = 0xFF335577;
      await settleQueue();
      await auth.signOut();
      host.syncResponse!.complete({'enabled': true, 'scheduledCount': 4});
      await settleQueue();
      expect(controller.enabled, isFalse);
      expect(controller.scheduledCount, 0);
      expect(host.calls.last.method, 'session');
      expect(host.calls.last.args['username'], isNull);
    },
  );

  test(
    'denied permission remains visible; disabling removes native queue',
    () async {
      host.deny = true;
      await controller.configure(reminders: true);
      expect(controller.notificationPermission, 'denied');
      expect(controller.schedulingWarning, '请开启通知');
      await controller.configure(reminders: false);
      expect(controller.enabled, isFalse);
      expect(host.calls.last.method, 'configure');
    },
  );

  test('background data changes are reconciled on resume', () async {
    await controller.configure(reminders: true);
    controller.setForeground(false);
    final before = host.calls.length;
    source.widgetSchedule = Schedule(
      term: source.widgetCalendar!.term,
      courses: const [],
    );
    source.notifyListeners();
    await settleQueue();
    expect(host.calls, hasLength(before));
    controller.setForeground(true);
    await settleQueue();
    expect(host.calls.last.method, 'sync');
    expect(host.calls.last.args['courses'], isEmpty);
  });

  test('native scheduling failures surface and can be retried', () async {
    host.syncResponse = Completer();
    final configuring = controller.configure(reminders: true);
    await settleQueue();
    host.syncResponse!.completeError(
      PlatformException(code: 'bad_plan', message: '课程时间不完整'),
    );
    await configuring;
    expect(controller.error, '课程时间不完整');
    expect(controller.busy, isFalse);
    host.syncResponse = null;
    await controller.refresh();
    expect(controller.error, isNull);
  });

  test('startup recovery does not clear persisted native reminders', () async {
    final restoring = Completer<AuthSession?>();
    final repository = FakeAuthRepository()..onRead = () => restoring.future;
    final delayedAuth = AuthController(repository: repository);
    final delayedHost = ReminderHost()..enabled = true;
    final delayedController = CourseActivityController(
      auth: delayedAuth,
      source: source,
      host: delayedHost,
      supportedPlatform: true,
      now: () => DateTime.utc(2026, 10, 5),
    );
    final restore = delayedAuth.restore();
    await settleQueue();
    expect(delayedHost.calls, isEmpty);
    restoring.complete(testSession());
    await restore;
    await settleQueue();
    expect(delayedHost.calls.first.method, 'session');
    expect(delayedHost.calls.first.args['username'], isNotNull);
    expect(delayedHost.calls.last.method, 'sync');
    delayedController.dispose();
    delayedAuth.dispose();
  });
}
