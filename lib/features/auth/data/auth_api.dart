import 'package:dio/dio.dart';

import '../domain/auth_models.dart';

class AuthApi {
  AuthApi(this._dio, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final Dio _dio;
  final DateTime Function() _now;

  Future<AuthSession> signIn({
    required String username,
    required String password,
    String? captcha,
  }) async {
    final data = await _request(
      'POST',
      '/api/v1/auth/login',
      data: {
        'username': username,
        'password': password,
        if (captcha != null && captcha.trim().isNotEmpty)
          'captcha': captcha.trim(),
      },
    );
    return AuthSession.fromJson(data, now: _now(), fallbackUsername: username);
  }

  Future<AuthSession> refresh(AuthSession session) async {
    final data = await _request(
      'POST',
      '/api/v1/auth/refresh',
      token: session.accessToken,
    );
    return AuthSession.fromJson(data, now: _now(), fallback: session);
  }

  Future<void> revoke(AuthSession session) async {
    await _request(
      'POST',
      '/api/v1/auth/logout',
      token: session.accessToken,
      requireData: false,
    );
  }

  Future<WechatChallenge> startWechat() async {
    final data = await _request('POST', '/api/v1/auth/wechat/start');
    return WechatChallenge.fromJson(data, now: _now());
  }

  Future<WechatResult> checkWechat(WechatChallenge challenge) async {
    final data = await _request(
      'GET',
      '/api/v1/auth/wechat/status',
      query: {'state': challenge.state},
    );
    return _wechatResult(data);
  }

  Future<WechatResult> completeWechat(
    WechatChallenge challenge, {
    required String ticket,
  }) async {
    final data = await _request(
      'POST',
      '/api/v1/auth/wechat/complete',
      data: {'state': challenge.state, 'ticket': ticket},
    );
    return _wechatResult(data);
  }

  Future<WechatResult> _wechatResult(Map<String, dynamic> data) async {
    switch (data['status']) {
      case 'pending':
        return const WechatResult(WechatStatus.pending);
      case 'expired':
        return const WechatResult(WechatStatus.expired);
      case 'error':
        return const WechatResult(WechatStatus.error);
      case 'success':
        // The WeChat response's expiresInSeconds may describe the QR session.
        // Query the API session for the actual access token expiration.
        final preliminary = AuthSession.fromJson(
          {...data}..remove('expiresInSeconds'),
          now: _now(),
          fallbackSource: 'wechat',
        );
        final details = await _request(
          'GET',
          '/api/v1/auth/session',
          token: preliminary.accessToken,
        );
        final session = AuthSession.fromJson(
          {...details, 'accessToken': preliminary.accessToken},
          now: _now(),
          fallback: preliminary,
        );
        return WechatResult(WechatStatus.success, session: session);
      default:
        throw const AuthFailure(
          AuthFailureKind.invalidResponse,
          '扫码状态无法识别，请重新获取二维码',
        );
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
    String? token,
    bool requireData = true,
  }) async {
    final Response<Object?> response;
    try {
      response = await _dio.request<Object?>(
        path,
        data: method == 'POST' ? data ?? <String, dynamic>{} : null,
        queryParameters: query,
        options: Options(
          method: method,
          followRedirects: false,
          validateStatus: (_) => true,
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
    } on DioException catch (error) {
      if (error.type == DioExceptionType.badCertificate) {
        throw const AuthFailure(AuthFailureKind.network, '无法建立安全连接，请稍后重试');
      }
      throw const AuthFailure(AuthFailureKind.network, '网络连接失败，请检查网络后重试');
    } catch (_) {
      throw const AuthFailure(
        AuthFailureKind.invalidResponse,
        '无法解析服务器响应，请稍后重试',
      );
    }
    final status = response.statusCode ?? 0;
    if (status == 401 || status == 403) {
      throw AuthFailure(
        token == null ? AuthFailureKind.rejected : AuthFailureKind.unauthorized,
        token == null ? '登录未通过，请检查账号信息或稍后重试' : '登录已失效，请重新登录',
      );
    }
    if (status >= 500 || status == 429) {
      throw const AuthFailure(AuthFailureKind.server, '服务暂时不可用，请稍后重试');
    }
    if (status < 200 || status >= 300) {
      throw const AuthFailure(AuthFailureKind.rejected, '请求未完成，请检查输入或稍后重试');
    }
    final body = response.data;
    if (body is! Map || body['ok'] is! bool) {
      throw const AuthFailure(
        AuthFailureKind.invalidResponse,
        '服务器响应格式异常，请稍后重试',
      );
    }
    if (body['ok'] != true) {
      // OpenAPI has only an unstructured error string. Do not guess that a
      // business rejection means the token expired, or expose raw backend text.
      throw const AuthFailure(AuthFailureKind.rejected, '请求未通过，请检查账号信息或稍后重试');
    }
    if (!requireData) return const {};
    if (body['data'] is! Map<String, dynamic>) {
      throw const AuthFailure(AuthFailureKind.invalidResponse, '服务器没有返回有效登录信息');
    }
    return body['data'] as Map<String, dynamic>;
  }
}
