import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/auth/data/auth_api.dart';
import 'package:xinli_lite/features/auth/domain/auth_models.dart';

class StubAdapter implements HttpClientAdapter {
  StubAdapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object body, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

void main() {
  final now = DateTime.utc(2026, 10, 8);
  late Dio dio;
  late AuthApi api;
  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
    api = AuthApi(dio, now: () => now);
  });
  tearDown(() => dio.close());

  test('password request matches contract and parses expiry', () async {
    final adapter = StubAdapter(
      (request) => jsonBody({
        'ok': true,
        'data': {'accessToken': 'secret-token', 'expiresInSeconds': 3600},
      }),
    );
    dio.httpClientAdapter = adapter;
    final session = await api.signIn(
      username: 'student',
      password: ' secret ',
      captcha: ' abc ',
    );
    final request = adapter.requests.single;
    expect(request.path, '/api/v1/auth/login');
    expect(request.method, 'POST');
    expect(request.followRedirects, isFalse);
    expect(request.data, {
      'username': 'student',
      'password': ' secret ',
      'captcha': 'abc',
    });
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(session.username, 'student');
    expect(session.expiresAt, now.add(const Duration(hours: 1)));
    expect(session.toString(), isNot(contains('secret-token')));
  });

  test('refresh uses bearer header and requires a rotated token', () async {
    final adapter = StubAdapter(
      (request) => jsonBody({
        'ok': true,
        'data': {'accessToken': 'new-token', 'expiresAt': 1791421200},
      }),
    );
    dio.httpClientAdapter = adapter;
    final old = AuthSession(
      accessToken: 'old-token',
      username: 'student',
      source: 'wechat',
      expiresAt: now,
    );
    final fresh = await api.refresh(old);
    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer old-token',
    );
    expect(fresh.accessToken, 'new-token');
    expect(fresh.source, 'wechat');
    expect(fresh.username, 'student');
  });

  test('logout accepts ok response with no data', () async {
    dio.httpClientAdapter = StubAdapter((_) => jsonBody({'ok': true}));
    await api.revoke(
      AuthSession(
        accessToken: 'token',
        username: '',
        source: 'password',
        expiresAt: now,
      ),
    );
  });

  for (final status in [401, 403, 429, 500]) {
    test(
      'HTTP $status is classified without exposing backend errors',
      () async {
        dio.httpClientAdapter = StubAdapter(
          (_) => jsonBody({
            'ok': false,
            'error': 'password=secret token=private',
          }, status: status),
        );
        await expectLater(
          api.signIn(username: 'student', password: 'secret'),
          throwsA(
            isA<AuthFailure>()
                .having(
                  (e) => e.kind,
                  'kind',
                  status >= 429
                      ? AuthFailureKind.server
                      : AuthFailureKind.rejected,
                )
                .having(
                  (e) => e.message,
                  'redacted',
                  isNot(contains('secret')),
                ),
          ),
        );
      },
    );
  }

  test('401 on protected endpoint is unauthorized', () async {
    dio.httpClientAdapter = StubAdapter(
      (_) => jsonBody({'ok': false}, status: 401),
    );
    await expectLater(
      api.refresh(
        AuthSession(
          accessToken: 'x',
          username: '',
          source: 'password',
          expiresAt: now,
        ),
      ),
      throwsA(
        isA<AuthFailure>().having(
          (e) => e.kind,
          'kind',
          AuthFailureKind.unauthorized,
        ),
      ),
    );
  });

  test(
    'business failure does not guess token expiration from an error string',
    () async {
      dio.httpClientAdapter = StubAdapter(
        (_) => jsonBody({'ok': false, 'error': 'token expired secret'}),
      );
      await expectLater(
        api.refresh(
          AuthSession(
            accessToken: 'x',
            username: '',
            source: 'password',
            expiresAt: now,
          ),
        ),
        throwsA(
          isA<AuthFailure>().having(
            (e) => e.kind,
            'kind',
            AuthFailureKind.rejected,
          ),
        ),
      );
    },
  );

  for (final body in [
    <String, dynamic>{},
    {'ok': true},
    {'ok': true, 'data': {}},
    {'ok': true, 'data': []},
  ]) {
    test('rejects invalid success response $body', () async {
      dio.httpClientAdapter = StubAdapter((_) => jsonBody(body));
      await expectLater(
        api.signIn(username: 'student', password: 'secret'),
        throwsA(
          isA<AuthFailure>().having(
            (e) => e.kind,
            'kind',
            AuthFailureKind.invalidResponse,
          ),
        ),
      );
    });
  }

  test('transport failure exposes neither request nor credentials', () async {
    dio.httpClientAdapter = StubAdapter(
      (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
        message: 'secret-password',
      ),
    );
    await expectLater(
      api.signIn(username: 'student', password: 'secret-password'),
      throwsA(
        isA<AuthFailure>()
            .having((e) => e.kind, 'kind', AuthFailureKind.network)
            .having(
              (e) => e.toString(),
              'redacted',
              isNot(contains('secret-password')),
            ),
      ),
    );
  });

  test(
    'WeChat success resolves actual API expiration using session endpoint',
    () async {
      final adapter = StubAdapter((options) {
        if (options.path.endsWith('/status')) {
          return jsonBody({
            'ok': true,
            'data': {
              'status': 'success',
              'accessToken': 'wechat-token',
              'expiresInSeconds': 30,
            },
          });
        }
        expect(options.path, '/api/v1/auth/session');
        expect(options.headers['Authorization'], 'Bearer wechat-token');
        return jsonBody({
          'ok': true,
          'data': {'username': 'student', 'expiresInSeconds': 2592000},
        });
      });
      dio.httpClientAdapter = adapter;
      final result = await api.checkWechat(
        WechatChallenge(
          state: 'state-1',
          authUrl: Uri.parse('https://cas.xjit.edu.cn/cas/federatedRedirect'),
          serviceUrl: Uri.parse(
            'https://superapp.xjit.edu.cn/pages/tab/index/index',
          ),
          expiresAt: now.add(const Duration(minutes: 10)),
        ),
      );
      expect(adapter.requests.first.queryParameters, {'state': 'state-1'});
      expect(result.session?.expiresAt, now.add(const Duration(days: 30)));
      expect(result.session?.source, 'wechat');
    },
  );
}
