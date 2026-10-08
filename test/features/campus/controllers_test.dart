import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../support/fakes.dart';
import 'support.dart';

Future<void> nextEvent() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'query switch discards late response and identical requests share work',
    () async {
      final resource = ResourceController<String>('schedule');
      addTearDown(resource.dispose);
      final a = Completer<String>();
      final b = Completer<String>();
      final first = resource.load(() => a.future, key: 'A');
      expect(
        identical(first, resource.load(() async => 'must not run', key: 'A')),
        isTrue,
      );
      await nextEvent();
      final second = resource.load(() => b.future, key: 'B');
      await nextEvent();
      b.complete('new');
      await second;
      a.complete('old');
      await first;
      expect(resource.state.data, 'new');
      expect(resource.state.key, 'B');
    },
  );

  test(
    'refresh failure retains old data but changed-query failure does not',
    () async {
      final resource = ResourceController<List<int>>('grades');
      addTearDown(resource.dispose);
      await resource.load(() async => [1], key: 'A');
      await resource.load(
        () async =>
            throw const CampusFailure(CampusFailureKind.network, 'offline'),
        key: 'A',
        refresh: true,
      );
      expect(resource.state.data, [1]);
      expect(resource.state.isStale, isTrue);
      await resource.load(
        () async =>
            throw const CampusFailure(CampusFailureKind.network, 'offline'),
        key: 'B',
      );
      expect(resource.state.data, isNull);
      await resource.load(() async => [], key: 'B');
      expect(resource.state.phase, ResourcePhase.ready);
      expect(resource.state.data, isEmpty);
    },
  );

  test('reset before scheduled request prevents network dispatch', () async {
    final resource = ResourceController<int>('profile');
    addTearDown(resource.dispose);
    var calls = 0;
    final load = resource.load(() async => ++calls);
    resource.reset();
    await load;
    expect(calls, 0);
    expect(resource.state.phase, ResourcePhase.idle);
  });

  test(
    'home modules settle independently and history does not overwrite today',
    () async {
      final auth = AuthController(repository: FakeAuthRepository());
      final repo = FakeCampusRepository()
        ..onProfile = () async {
          throw const CampusFailure(CampusFailureKind.network, 'offline');
        }
        ..onSchedule = (term) async =>
            Schedule(term: term ?? 'current', courses: []);
      final campus = CampusController(auth: auth, repository: repo);
      addTearDown(() {
        campus.dispose();
        auth.dispose();
      });
      await campus.home.load();
      expect(campus.home.state.profile.phase, ResourcePhase.failure);
      expect(campus.home.state.schedule.phase, ResourcePhase.ready);
      expect(campus.home.state.undatedExams.single.courseName, '课程');
      expect(campus.home.state.day!.status, DayScheduleStatus.needsCalendar);
      await campus.loadSchedule(term: 'old');
      expect(campus.schedule.state.data!.term, 'old');
      expect(campus.home.state.schedule.data!.term, 'current');
    },
  );

  test('logout clears data and suppresses in-flight personal data', () async {
    final auth = AuthController(
      repository: FakeAuthRepository(stored: testSession()),
    );
    await auth.restore();
    final delayed = Completer<StudentProfile>();
    final repo = FakeCampusRepository();
    final campus = CampusController(auth: auth, repository: repo);
    addTearDown(() {
      campus.dispose();
      auth.dispose();
    });
    await campus.loadProfile();
    expect(campus.profile.state.hasData, isTrue);
    repo.onProfile = () => delayed.future;
    final request = campus.loadProfile(refresh: true);
    await nextEvent();
    await auth.signOut();
    expect(campus.profile.state.hasData, isFalse);
    delayed.complete(const StudentProfile(studentId: 'old', name: 'old'));
    await request;
    expect(campus.profile.state.phase, ResourcePhase.idle);
    await auth.signIn(username: 'new', password: 'password');
    expect(campus.profile.state.data, isNull);
  });

  test(
    'token rotation does not clear campus data; old token cannot sign out new',
    () async {
      final auth = AuthController(
        repository: FakeAuthRepository(stored: testSession()),
      );
      await auth.restore();
      final campus = CampusController(
        auth: auth,
        repository: FakeCampusRepository(),
      );
      addTearDown(() {
        campus.dispose();
        auth.dispose();
      });
      await campus.loadProfile();
      final revision = auth.sessionRevision;
      await auth.refreshSession(force: true);
      expect(auth.sessionRevision, revision);
      expect(campus.profile.state.hasData, isTrue);
      await auth.invalidateSession('outdated-token');
      expect(auth.state.isAuthenticated, isTrue);
      await auth.invalidateSession(auth.state.session!.accessToken);
      expect(auth.state.isAuthenticated, isFalse);
      expect(campus.profile.state.hasData, isFalse);
    },
  );

  test('invalidated-session storage failure supports retry signout', () async {
    final store = FakeAuthRepository(stored: testSession())..clearFailures = 1;
    final auth = AuthController(repository: store);
    addTearDown(auth.dispose);
    await auth.restore();
    await auth.invalidateSession(auth.state.session!.accessToken);
    expect(auth.state.failure!.operation, AuthOperation.signOut);
    await auth.signOut();
    expect(store.stored, isNull);
  });

  test(
    'transaction paging deduplicates ids, keeps data on error and retries same page',
    () async {
      final requested = <int>[];
      var fail = false;
      final repo = FakeCampusRepository()
        ..onTransactions = (query, page) async {
          requested.add(page);
          if (fail) {
            throw const CampusFailure(CampusFailureKind.network, 'offline');
          }
          return TransactionPage.fromJson({
            'pageNo': page,
            'pageSize': 2,
            'transactions': [
              if (page < 3) {'journo': 'shared', 'amount': '1'},
              if (page < 3) {'journo': '$page', 'amount': '2'},
            ],
          });
        };
      final controller = TransactionsController(repo);
      addTearDown(controller.dispose);
      await controller.load(query: const TransactionQuery(pageSize: 2));
      fail = true;
      await controller.loadMore();
      expect(controller.state.items.length, 2);
      expect(controller.state.pageNo, 1);
      fail = false;
      final more = controller.loadMore();
      expect(identical(more, controller.loadMore()), isTrue);
      await more;
      expect(controller.state.items.length, 3);
      await controller.loadMore();
      expect(controller.state.hasMore, isFalse);
      expect(requested, [1, 2, 2, 3]);
    },
  );

  test('transaction filter switch ignores earlier page result', () async {
    final old = Completer<TransactionPage>();
    final repo = FakeCampusRepository()
      ..onTransactions = (query, page) => query.tradeType == '1'
          ? old.future
          : Future.value(
              TransactionPage.fromJson({
                'pageNo': 1,
                'pageSize': 20,
                'transactions': [],
              }),
            );
    final controller = TransactionsController(repo);
    addTearDown(controller.dispose);
    final first = controller.load(
      query: const TransactionQuery(tradeType: '1'),
    );
    await nextEvent();
    await controller.load(query: const TransactionQuery(tradeType: '2'));
    old.complete(TransactionPage.fromJson(example('newcard.transactions')));
    await first;
    expect(controller.state.items, isEmpty);
  });

  group('payments', () {
    late FakeCampusRepository repo;
    late PaymentController controller;
    const method = PayMethod(code: '06', name: '余额');
    setUp(() {
      repo = FakeCampusRepository();
      controller = PaymentController(repo);
    });
    tearDown(() => controller.dispose());

    test('requires correct room config and payment password', () async {
      await controller.submitElectricity(
        room: '9#312',
        amount: '30',
        method: method,
      );
      expect(repo.charges, 0);
      await controller.loadElectricityConfig('9#312');
      await controller.submitElectricity(
        room: 'wrong',
        amount: '30',
        method: method,
        paymentPassword: 'p',
      );
      expect(repo.charges, 0);
      await controller.submitElectricity(
        room: '9#312',
        amount: '30',
        method: method,
      );
      expect(controller.state.failure!.kind, CampusFailureKind.validation);
      expect(repo.charges, 0);
    });
    test(
      'duplicate taps cause exactly one charge; completed needs explicit new flow',
      () async {
        await controller.loadElectricityConfig('9#312');
        final result = Completer<PaymentOrder>();
        repo.onPay = () => result.future;
        final first = controller.submitElectricity(
          room: '9#312',
          amount: '30',
          method: method,
          paymentPassword: ' secret ',
        );
        final second = controller.submitElectricity(
          room: '9#312',
          amount: '30',
          method: method,
          paymentPassword: ' secret ',
        );
        expect(identical(first, second), isTrue);
        await nextEvent();
        expect(repo.charges, 1);
        expect(repo.receivedPassword, ' secret ');
        result.complete(
          PaymentOrder.fromJson(example('newcard.electricity.recharge.pay')),
        );
        await first;
        expect(controller.state.phase, PaymentPhase.completed);
        await controller.submitElectricity(
          room: '9#312',
          amount: '30',
          method: method,
          paymentPassword: 'p',
        );
        expect(repo.charges, 1);
      },
    );
    test(
      'timeout remains locked until result checked and a new flow started',
      () async {
        await controller.loadElectricityConfig('9#312');
        repo.onPay = () async => throw const CampusFailure(
          CampusFailureKind.outcomeUnknown,
          'unknown',
        );
        await controller.submitElectricity(
          room: '9#312',
          amount: '30',
          method: method,
          paymentPassword: 'p',
        );
        expect(controller.state.phase, PaymentPhase.outcomeUnknown);
        controller.beginNewPayment();
        expect(controller.state.phase, PaymentPhase.outcomeUnknown);
        await controller.submitElectricity(
          room: '9#312',
          amount: '30',
          method: method,
          paymentPassword: 'p',
        );
        expect(repo.charges, 1);
        controller.beginNewPayment(previousOutcomeChecked: true);
        expect(controller.state.phase, PaymentPhase.idle);
        expect(controller.electricityConfig.state.data, isNull);
      },
    );
    test(
      'card order and returning from external payment never imply completion',
      () async {
        await controller.loadCardConfig();
        await controller.submitCard(
          amount: '50',
          method: controller.cardConfig.state.data!.payMethods.first,
        );
        expect(controller.state.phase, PaymentPhase.awaitingExternalPayment);
        controller.beginNewPayment();
        expect(controller.state.phase, PaymentPhase.awaitingExternalPayment);
      },
    );
    test('session reset stops a queued payment before transmission', () async {
      await controller.loadElectricityConfig('9#312');
      final task = controller.submitElectricity(
        room: '9#312',
        amount: '30',
        method: method,
        paymentPassword: 'p',
      );
      controller.resetSession();
      await task;
      expect(repo.charges, 0);
    });
  });

  testWidgets('payment code expires, refreshes and clears in background', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 8);
    final repo = FakeCampusRepository()
      ..onCode = () async => CampusCode.fromJson({
        ...example('newcard.campus_code.qrcode'),
        'expiresInSeconds': 2,
      }, requestedAt: now);
    final controller = CampusCodeController(repo, now: () => now);
    final first = controller.setVisible(true);
    await tester.pump(const Duration(milliseconds: 1));
    await first;
    expect(controller.usableCode, isNotNull);
    expect(repo.codeCalls, 1);
    now = now.add(const Duration(seconds: 2));
    expect(controller.usableCode, isNull);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 1));
    expect(repo.codeCalls, 2);
    await controller.setForeground(false);
    expect(controller.state.data, isNull);
    await tester.pump(const Duration(minutes: 1));
    expect(repo.codeCalls, 2);
    controller.dispose();
  });

  test('late payment code cannot reappear after hiding page', () async {
    final result = Completer<CampusCode>();
    final repo = FakeCampusRepository()..onCode = () => result.future;
    final controller = CampusCodeController(repo);
    addTearDown(controller.dispose);
    final first = controller.setVisible(true);
    await nextEvent();
    await controller.setVisible(false);
    result.complete(
      CampusCode.fromJson(
        example('newcard.campus_code.qrcode'),
        requestedAt: DateTime.now(),
      ),
    );
    await first;
    expect(controller.state.data, isNull);
  });
}
