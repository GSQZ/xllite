import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/campus/campus.dart';
import 'package:xinli_lite/features/campus/data/campus_api.dart';
import 'package:xinli_lite/features/campus/data/campus_store.dart';
import 'package:xinli_lite/features/campus/data/default_campus_repository.dart';
import '../../support/fakes.dart';
import 'support.dart';

class MemoryStorage implements CampusStorage {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async {
    if (fail) throw StateError('unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String? value) async {
    if (fail) throw StateError('unavailable');
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

class LocalFake extends FakeCampusRepository implements CampusLocalData {
  final prefs = <String, String>{};
  bool failWrite = false;
  bool failElectricity = false;
  @override
  Future<ElectricityAccount> electricity(String roomQuery) async {
    if (failElectricity) {
      throw const CampusFailure(CampusFailureKind.network, 'offline');
    }
    return super.electricity(roomQuery);
  }

  @override
  Future<CachedData<T>?> readCached<T>(String operation, {Object? key}) async =>
      null;
  @override
  Future<String?> readPreference(String key) async => prefs[key];
  @override
  Future<void> writePreference(String key, String? value) async {
    if (failWrite) throw StateError('unavailable');
    if (value == null) {
      prefs.remove(key);
    } else {
      prefs[key] = value;
    }
  }

  @override
  Future<void> clearCache() async {}
}

void main() {
  test(
    'snapshots survive restart, expire, stay isolated and preserve preferences on clear',
    () async {
      var now = DateTime.utc(2026, 10, 9);
      final storage = MemoryStorage();
      final store = CampusStore(storage, now: () => now);
      await Future.wait([
        store.put('A', 'profile', {'name': 'A'}),
        store.put('A', 'schedule', {'courses': []}),
      ]);
      await store.setPreference('A', 'room', '9#312');
      final restarted = CampusStore(storage, now: () => now);
      expect(
        (await restarted.read(
          'A',
          'profile',
          const Duration(days: 1),
        ))!.data['name'],
        'A',
      );
      expect(
        await restarted.read('B', 'profile', const Duration(days: 1)),
        isNull,
      );
      expect(
        await restarted.read('A', 'schedule', const Duration(days: 1)),
        isNotNull,
      );
      now = now.add(const Duration(days: 2));
      expect(
        await restarted.read('A', 'profile', const Duration(days: 1)),
        isNull,
      );
      await restarted.clear('A');
      expect(await restarted.preference('A', 'room'), '9#312');
      expect(
        await restarted.read('A', 'schedule', const Duration(days: 30)),
        isNull,
      );
    },
  );
  test('cache is bounded and corrupt storage is a miss', () async {
    final storage = MemoryStorage();
    final store = CampusStore(storage);
    for (var i = 0; i < 40; i++) {
      await store.put('A', '$i', {'value': i});
    }
    expect(await store.read('A', '0', const Duration(days: 1)), isNull);
    expect(await store.read('A', '39', const Duration(days: 1)), isNotNull);
    for (final key in storage.values.keys.toList()) {
      storage.values[key] = 'corrupt';
    }
    expect(
      await CampusStore(storage).read('A', '39', const Duration(days: 1)),
      isNull,
    );
  });
  test(
    'cached data appears during refresh and retains real age on failure; reset discards late reads',
    () async {
      final resource = ResourceController<String>('test');
      addTearDown(resource.dispose);
      final at = DateTime.utc(2026, 9, 1);
      resource.readCache = (_) async => CachedData('cached', at);
      final request = Completer<String>();
      final done = resource.load(() => request.future);
      await Future<void>.delayed(Duration.zero);
      expect(resource.state.data, 'cached');
      expect(resource.state.fromCache, isTrue);
      expect(resource.state.isRefreshing, isTrue);
      request.completeError(
        const CampusFailure(CampusFailureKind.network, 'offline'),
      );
      await done;
      expect(resource.state.updatedAt, at);
      expect(resource.state.isStale, isTrue);
      resource.reset();
      final cache = Completer<CachedData<String>?>();
      resource.readCache = (_) => cache.future;
      var calls = 0;
      final abandoned = resource.load(() async {
        calls++;
        return 'new';
      });
      await Future<void>.delayed(Duration.zero);
      resource.reset();
      cache.complete(CachedData('old', at));
      await abandoned;
      expect(calls, 0);
      expect(resource.state.data, isNull);
    },
  );
  test(
    'freshness skips repeated visits, refresh and expiry request live data',
    () async {
      var now = DateTime.utc(2026, 10, 9);
      var count = 0;
      final r = ResourceController<int>('test', now: () => now);
      addTearDown(r.dispose);
      Future<int> fetch() async => ++count;
      await r.load(fetch);
      await r.load(fetch);
      expect(count, 1);
      await r.load(fetch, refresh: true);
      expect(count, 2);
      now = now.add(const Duration(minutes: 6));
      await r.load(fetch);
      expect(count, 3);
    },
  );
  test(
    'repository coalesces reads, isolates accounts and never caches payment or QR responses',
    () async {
      final storage = MemoryStorage();
      final store = CampusStore(storage);
      var user = 'A';
      final session = FakeSession();
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      final adapter = StubAdapter((request) async {
        final op = (request.data as Map)['feature'] as String;
        return body({'ok': true, 'data': example(op)});
      });
      dio.httpClientAdapter = adapter;
      addTearDown(() => dio.close());
      final repo = DefaultCampusRepository(
        CampusApi(dio, session),
        store: store,
        account: () => user,
      );
      await Future.wait([repo.profile(), repo.profile()]);
      expect(adapter.requests, hasLength(1));
      await repo.writePreference('room', '9#312'); // Flushes the write queue.
      expect(await repo.readCached<StudentProfile>('jw.profile'), isNotNull);
      user = 'B';
      expect(await repo.readCached<StudentProfile>('jw.profile'), isNull);
      expect(await repo.readPreference('room'), isNull);
      user = 'A';
      await repo.campusCode();
      await repo.cardRechargeConfig();
      expect(storage.values.values.join(), isNot(contains('qrcode')));
      expect(await repo.readCached<Object>('newcard.recharge.config'), isNull);
      storage.fail = true;
      expect((await repo.profile()).studentId, isNotEmpty);
    },
  );
  test(
    'successful room query survives controller recreation; failure does not overwrite it',
    () async {
      final auth = AuthController(
        repository: FakeAuthRepository(stored: testSession()),
      );
      await auth.restore();
      addTearDown(auth.dispose);
      final repo = LocalFake();
      var campus = CampusController(auth: auth, repository: repo);
      await campus.loadElectricity(' 9#312 ');
      expect(repo.prefs['room'], '9#312');
      campus.dispose();
      campus = CampusController(auth: auth, repository: repo);
      addTearDown(campus.dispose);
      await campus.restorePreferences();
      expect(campus.roomQuery, '9#312');
      expect(campus.electricity.state.data, isNotNull);
      await campus.clearCache();
      expect(repo.prefs['room'], '9#312');
    },
  );
  test(
    'pending payment survives controller recreation without storing a password; no automatic second debit',
    () async {
      final repo = LocalFake()
        ..onPay = () async => throw const CampusFailure(
          CampusFailureKind.outcomeUnknown,
          'timeout',
        );
      var payments = PaymentController(repo);
      await payments.loadElectricityConfig('9#312');
      await payments.submitElectricity(
        room: '9#312',
        amount: '30',
        method: payments.electricityConfig.state.data!.payMethods.first,
        paymentPassword: 'private-password',
      );
      expect(repo.charges, 1);
      expect(repo.prefs['pendingPayment'], isNotNull);
      expect(repo.prefs.toString(), isNot(contains('private-password')));
      payments.dispose();
      payments = PaymentController(repo);
      addTearDown(payments.dispose);
      await payments.loadElectricityConfig('9#312');
      expect(payments.state.phase, PaymentPhase.outcomeUnknown);
      expect(payments.state.room, '9#312');
      await payments.submitElectricity(
        room: '9#312',
        amount: '30',
        method: payments.electricityConfig.state.data!.payMethods.first,
        paymentPassword: 'p',
      );
      expect(repo.charges, 1);
      payments.beginNewPayment(previousOutcomeChecked: true);
      await Future<void>.delayed(Duration.zero);
      expect(repo.prefs['pendingPayment'], isNull);
    },
  );
  test('journal failure prevents submission', () async {
    final repo = LocalFake();
    final p = PaymentController(repo);
    addTearDown(p.dispose);
    await p.loadElectricityConfig('9#312');
    repo.failWrite = true;
    await p.submitElectricity(
      room: '9#312',
      amount: '30',
      method: p.electricityConfig.state.data!.payMethods.first,
      paymentPassword: 'p',
    );
    expect(repo.charges, 0);
    expect(p.state.phase, PaymentPhase.failed);
  });
}
