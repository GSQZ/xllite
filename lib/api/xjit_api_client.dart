import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import 'xjit_features.dart';

final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 45),
      sendTimeout: const Duration(seconds: 12),
      headers: const {'Content-Type': 'application/json'},
    ),
  );
});

final xjitApiClientProvider = Provider<XjitApiClient>((ref) {
  return XjitApiClient(ref.watch(dioProvider));
});

class XjitApiClient {
  const XjitApiClient(this._dio);

  final Dio _dio;

  Future<bool> health() async {
    final response = await _dio.get<Map<String, dynamic>>('/health');
    final data = response.data;
    return data != null && data['ok'] == true;
  }

  Future<Map<String, dynamic>> run(
    XjitFeature feature, {
    required String username,
    required String password,
    Map<String, dynamic> params = const {},
    String? captcha,
    bool? rememberMe,
  }) async {
    final payload = <String, dynamic>{
      'username': username,
      'password': password,
      'feature': feature.value,
      'params': params,
    };
    if (captcha != null && captcha.isNotEmpty) {
      payload['captcha'] = captcha;
    }
    if (rememberMe != null) {
      payload['rememberMe'] = rememberMe;
    }

    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/run',
      data: payload,
    );
    final body = response.data;
    if (body == null) {
      throw const XjitApiException('接口没有返回数据');
    }
    if (body['ok'] != true) {
      throw XjitApiException(body['error']?.toString() ?? '请求失败');
    }
    final data = body['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{};
  }
}

class XjitApiException implements Exception {
  const XjitApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
