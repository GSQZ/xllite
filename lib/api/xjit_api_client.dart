import 'dart:convert';

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
      validateStatus: (status) => status != null && status < 500,
    ),
  );
});

final xjitApiClientProvider = Provider<XjitApiClient>((ref) {
  return XjitApiClient(ref.watch(dioProvider));
});

final xjitApiCacheProvider = Provider<XjitApiCache>((ref) {
  return XjitApiCache(ref.watch(xjitApiClientProvider));
});

class XjitApiCache {
  XjitApiCache(this._client);

  final XjitApiClient _client;
  final Map<String, Future<Map<String, dynamic>>> _runCache = {};
  Future<bool>? _healthCache;

  Future<bool> health({bool forceRefresh = false}) {
    if (!forceRefresh && _healthCache != null) {
      return _healthCache!;
    }

    late final Future<bool> future;
    future = _client.health().catchError((Object error, StackTrace stackTrace) {
      if (identical(_healthCache, future)) {
        _healthCache = null;
      }
      Error.throwWithStackTrace(error, stackTrace);
    });
    _healthCache = future;
    return future;
  }

  Future<Map<String, dynamic>> run(
    XjitFeature feature, {
    required String username,
    required String password,
    Map<String, dynamic> params = const {},
    bool forceRefresh = false,
  }) {
    final key = _runKey(username: username, feature: feature, params: params);
    final cached = _runCache[key];
    if (!forceRefresh && cached != null) {
      return cached;
    }

    late final Future<Map<String, dynamic>> future;
    future = _client
        .run(feature, username: username, password: password, params: params)
        .catchError((Object error, StackTrace stackTrace) {
          if (identical(_runCache[key], future)) {
            _runCache.remove(key);
          }
          Error.throwWithStackTrace(error, stackTrace);
        });
    _runCache[key] = future;
    return future;
  }

  void clear() {
    _healthCache = null;
    _runCache.clear();
  }

  String _runKey({
    required String username,
    required XjitFeature feature,
    required Map<String, dynamic> params,
  }) {
    return jsonEncode({
      'username': username,
      'feature': feature.value,
      'params': _normalize(params),
    });
  }

  Object? _normalize(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      return {
        for (final entry in entries)
          entry.key.toString(): _normalize(entry.value),
      };
    }
    if (value is List) {
      return value.map(_normalize).toList();
    }
    return value;
  }
}

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

    final Response<Object?> response;
    try {
      response = await _dio.post<Object?>('/api/v1/run', data: payload);
    } on DioException catch (error) {
      throw XjitApiException(_dioErrorMessage(error));
    }
    final body = _asMap(response.data);
    if (body == null) {
      final statusCode = response.statusCode;
      if (statusCode != null && statusCode >= 400) {
        throw XjitApiException('接口请求失败（HTTP $statusCode）');
      }
      throw const XjitApiException('接口没有返回数据');
    }
    if (body['ok'] != true) {
      throw XjitApiException(_errorMessage(body, response.statusCode));
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

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  String _errorMessage(Map<String, dynamic> body, int? statusCode) {
    final error = body['error'] ?? body['message'] ?? body['msg'];
    final text = error?.toString().trim();
    if (text != null && text.isNotEmpty) {
      return text;
    }
    if (statusCode != null && statusCode >= 400) {
      return '接口请求失败（HTTP $statusCode）';
    }
    return '请求失败';
  }

  String _dioErrorMessage(DioException error) {
    final body = _asMap(error.response?.data);
    if (body != null) {
      return _errorMessage(body, error.response?.statusCode);
    }
    final statusCode = error.response?.statusCode;
    if (statusCode != null) {
      return '接口请求失败（HTTP $statusCode）';
    }
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) {
      return message;
    }
    return '接口请求失败';
  }
}

class XjitApiException implements Exception {
  const XjitApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
