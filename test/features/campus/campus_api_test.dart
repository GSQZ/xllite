import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/campus/campus.dart';
import 'package:xinli_lite/features/campus/data/campus_api.dart';
import 'package:xinli_lite/features/campus/data/default_campus_repository.dart';

import 'support.dart';

void main() {
  late Dio dio;
  late FakeSession session;
  late CampusApi api;
  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
    session = FakeSession();
    api = CampusApi(dio, session);
  });
  tearDown(() => dio.close());

  for (final accountId in [null, '']) {
    test(
      'electricity config and payment accept absent account ID: $accountId',
      () async {
        final adapter = StubAdapter((r) {
          final data = example((r.data as Map)['feature'] as String);
          final account = data['account'] as Map<String, dynamic>;
          account.remove('utilityAccount');
          if (accountId != null) account['utilityAccount'] = accountId;
          return body({'ok': true, 'data': data});
        });
        dio.httpClientAdapter = adapter;
        final controller = PaymentController(DefaultCampusRepository(api));
        addTearDown(controller.dispose);

        await controller.loadElectricityConfig('9#312');
        expect(controller.electricityConfig.state.failure, isNull);
        final config = controller.electricityConfig.state.data!;
        expect(config.account.utilityAccount, isEmpty);
        expect(config.price.numericValue, 0.39);
        expect(config.needPaymentPassword, isTrue);
        expect(adapter.requests, hasLength(1));

        await controller.submitElectricity(
          room: '9#312',
          amount: '30',
          method: config.payMethods.single,
          paymentPassword: 'test-password',
        );
        expect(controller.state.phase, PaymentPhase.completed);
        expect(controller.state.order!.account!.utilityAccount, isEmpty);
        expect(adapter.requests, hasLength(2));
        expect(
          (adapter.requests.last.data as Map)['params']['roomQuery'],
          '9#312',
        );
      },
    );
  }

  test(
    'all 13 documented features have typed requests and responses',
    () async {
      final adapter = StubAdapter(
        (r) => body({
          'ok': true,
          'data': example((r.data as Map)['feature'] as String),
        }),
      );
      dio.httpClientAdapter = adapter;
      final repo = DefaultCampusRepository(api);
      expect((await repo.profile()).name, '姓名');
      expect(
        (await repo.schedule(term: ' 2025-2026-2 ')).courses.single.title,
        '课程名',
      );
      expect(
        (await repo.grades(mode: GradeMode.raw)).summary.weightedGradePoint,
        2.25,
      );
      expect((await repo.exams()).single.examTime, '考试时间');
      expect((await repo.training()).single.graduationYear, '毕业届别');
      expect((await repo.balance()).single.balance, '余额');
      expect(
        (await repo.transactions(const TransactionQuery(pageSize: 20))).pageNo,
        1,
      );
      final code = await repo.campusCode();
      expect(code.value, startsWith('付款码字符串'));
      expect(code.toString(), isNot(contains(code.value)));
      expect((await repo.cardRechargeConfig()).payMethods.length, 2);
      final order = await repo.createCardOrder(
        amount: MoneyAmount.parse('50'),
        method: const PayMethod(code: '01', name: '支付宝', tradeType: 'WAP'),
      );
      expect(order.result.type, PaymentResultType.htmlPost);
      expect(
        (await repo.electricity(' 9#312 ')).remainingElectricity.numericValue,
        28.15,
      );
      expect(
        (await repo.electricityRechargeConfig('9#312')).needPaymentPassword,
        isTrue,
      );
      final paid = await repo.payElectricity(
        roomQuery: '9#312',
        amount: MoneyAmount.parse('30'),
        method: const PayMethod(code: '06', name: '余额'),
        paymentPassword: ' secret ',
      );
      expect(paid.result.type, PaymentResultType.balancePayment);
      expect(
        adapter.requests.map((r) => (r.data as Map)['feature']).toSet(),
        examples.keys.toSet(),
      );
      for (final r in adapter.requests) {
        expect(r.path, '/api/v1/run');
        expect(r.method, 'POST');
        expect(r.followRedirects, isFalse);
        expect(r.headers['Authorization'], 'Bearer old-token');
        expect((r.data as Map).keys, unorderedEquals(['feature', 'params']));
      }
      expect((adapter.requests[1].data as Map)['params'], {
        'term': '2025-2026-2',
      });
      expect((adapter.requests[2].data as Map)['params'], {'mode': 'raw'});
      expect((adapter.requests.last.data as Map)['params'], {
        'roomQuery': '9#312',
        'amount': '30.00',
        'payCode': '06',
        'paymentPassword': ' secret ',
        'customfield': {},
      });
    },
  );

  test(
    '401 read rotates then replays exactly once with latest token',
    () async {
      final adapter = StubAdapter(
        (r) => r.headers['Authorization'] == 'Bearer old-token'
            ? body({'ok': false}, status: 401)
            : body({'ok': true, 'data': {}}),
      );
      dio.httpClientAdapter = adapter;
      await api.run(CampusFeature.profile);
      expect(adapter.requests.length, 2);
      expect(session.refreshes, 1);
    },
  );
  test('a second 401 invalidates only the rejected current token', () async {
    final adapter = StubAdapter((r) => body({'ok': false}, status: 401));
    dio.httpClientAdapter = adapter;
    await expectLater(
      api.run(CampusFeature.profile),
      throwsA(isA<CampusFailure>()),
    );
    expect(adapter.requests.length, 2);
    expect(session.invalidations, 1);
    expect(session.token, isNull);
  });
  test(
    'payment never replays even after successful 401 token renewal',
    () async {
      final adapter = StubAdapter((r) => body({'ok': false}, status: 401));
      dio.httpClientAdapter = adapter;
      await expectLater(
        api.run(CampusFeature.electricityPay),
        throwsA(isA<CampusFailure>()),
      );
      expect(adapter.requests.length, 1);
      expect(session.token, 'new-token');
      expect(session.invalidations, 0);
    },
  );
  test(
    'renewal network failure does not invalidate stored credentials',
    () async {
      session.onRefresh = () async =>
          throw const CampusFailure(CampusFailureKind.network, 'offline');
      dio.httpClientAdapter = StubAdapter((r) => body({}, status: 401));
      await expectLater(
        api.run(CampusFeature.profile),
        throwsA(
          isA<CampusFailure>().having(
            (e) => e.kind,
            'kind',
            CampusFailureKind.network,
          ),
        ),
      );
      expect(session.invalidations, 0);
    },
  );
  for (final status in [400, 403, 429, 500, 302]) {
    test(
      'HTTP $status classified with operation and no backend secrets',
      () async {
        dio.httpClientAdapter = StubAdapter(
          (r) =>
              body({'ok': false, 'error': 'password=secret'}, status: status),
        );
        await expectLater(
          api.run(CampusFeature.profile),
          throwsA(
            isA<CampusFailure>()
                .having((e) => e.operation, 'operation', 'jw.profile')
                .having((e) => e.toString(), 'safe', isNot(contains('secret')))
                .having(
                  (e) => e.kind,
                  'kind',
                  status == 403
                      ? CampusFailureKind.forbidden
                      : status >= 429
                      ? CampusFailureKind.server
                      : CampusFailureKind.rejected,
                ),
          ),
        );
        expect(session.invalidations, 0);
      },
    );
  }
  for (final feature in [
    CampusFeature.cardOrder,
    CampusFeature.electricityPay,
  ]) {
    test(
      '${feature.name} timeout and malformed success are outcomeUnknown',
      () async {
        for (final failure in ['timeout', 'malformed', 'server']) {
          final adapter = StubAdapter((r) {
            if (failure == 'timeout') {
              throw DioException(
                requestOptions: r,
                type: DioExceptionType.receiveTimeout,
                message: 'secret',
              );
            }
            return failure == 'server'
                ? body({}, status: 500)
                : body({'ok': true, 'data': []});
          });
          dio.httpClientAdapter = adapter;
          await expectLater(
            api.run(feature),
            throwsA(
              isA<CampusFailure>().having(
                (e) => e.kind,
                'kind',
                CampusFailureKind.outcomeUnknown,
              ),
            ),
          );
          expect(adapter.requests.length, 1);
        }
      },
    );
  }
  test('logout and same-account relogin discard a late response', () async {
    final response = Completer<ResponseBody>();
    final sent = Completer<void>();
    dio.httpClientAdapter = StubAdapter((r) {
      sent.complete();
      return response.future;
    });
    final result = api.run(CampusFeature.profile);
    final assertion = expectLater(
      result,
      throwsA(
        isA<CampusFailure>().having(
          (e) => e.kind,
          'kind',
          CampusFailureKind.cancelled,
        ),
      ),
    );
    await sent.future;
    session.revision += 2;
    response.complete(body({'ok': true, 'data': {}}));
    await assertion;
  });
  test('missing session sends no HTTP request', () async {
    session.token = null;
    final adapter = StubAdapter((r) => throw StateError('must not call'));
    dio.httpClientAdapter = adapter;
    await expectLater(
      api.run(CampusFeature.profile),
      throwsA(isA<CampusFailure>()),
    );
    expect(adapter.requests, isEmpty);
  });
  test(
    'malformed nonempty business data is not converted into empty success',
    () async {
      dio.httpClientAdapter = StubAdapter(
        (r) => body({
          'ok': true,
          'data': {'courses': null, 'term': 'x'},
        }),
      );
      await expectLater(
        DefaultCampusRepository(api).schedule(),
        throwsA(
          isA<CampusFailure>().having(
            (e) => e.kind,
            'kind',
            CampusFailureKind.invalidResponse,
          ),
        ),
      );
    },
  );
}
