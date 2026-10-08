import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

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
  Future<Directory>? _cacheDirectory;

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
    required String accessToken,
    Map<String, dynamic> params = const {},
    bool forceRefresh = false,
  }) {
    final key = _runKey(username: username, feature: feature, params: params);
    final cached = _runCache[key];
    if (!forceRefresh && cached != null) {
      return cached;
    }

    late final Future<Map<String, dynamic>> future;
    future =
        _runCached(
          key: key,
          feature: feature,
          accessToken: accessToken,
          params: params,
          forceRefresh: forceRefresh,
        ).catchError((Object error, StackTrace stackTrace) {
          if (identical(_runCache[key], future)) {
            _runCache.remove(key);
          }
          Error.throwWithStackTrace(error, stackTrace);
        });
    _runCache[key] = future;
    return future;
  }

  Future<void> clear() async {
    _healthCache = null;
    _runCache.clear();
    try {
      final directory = await _runCacheDirectory();
      _cacheDirectory = null;
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      _cacheDirectory = null;
    }
  }

  Future<Map<String, dynamic>> _runCached({
    required String key,
    required XjitFeature feature,
    required String accessToken,
    required Map<String, dynamic> params,
    required bool forceRefresh,
  }) async {
    if (!forceRefresh) {
      final diskCache = await _readRunCache(key);
      if (diskCache != null) {
        return diskCache;
      }
    }

    final data = await _client.run(
      feature,
      accessToken: accessToken,
      params: params,
    );
    await _writeRunCache(key, data);
    return data;
  }

  Future<Map<String, dynamic>?> _readRunCache(String key) async {
    try {
      final file = await _cacheFile(key);
      if (!await file.exists()) {
        return null;
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      final data = decoded['data'];
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
    } catch (_) {
      await _deleteRunCache(key);
    }
    return null;
  }

  Future<void> _writeRunCache(String key, Map<String, dynamic> data) async {
    try {
      final file = await _cacheFile(key);
      await file.writeAsString(jsonEncode({'data': data}), flush: true);
    } catch (_) {
      // Cache writes must never break the real request path.
    }
  }

  Future<void> _deleteRunCache(String key) async {
    try {
      final file = await _cacheFile(key);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Nothing useful to do for a broken cache file.
    }
  }

  Future<File> _cacheFile(String key) async {
    final directory = await _runCacheDirectory();
    final name = base64Url.encode(utf8.encode(key)).replaceAll('=', '');
    return File('${directory.path}/$name.json');
  }

  Future<Directory> _runCacheDirectory() async {
    final existing = _cacheDirectory;
    if (existing != null) {
      return existing;
    }
    final future = _createCacheDirectory();
    _cacheDirectory = future;
    return future;
  }

  Future<Directory> _createCacheDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final directory = Directory('${supportDirectory.path}/xjit_api_cache');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
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
    required String accessToken,
    Map<String, dynamic> params = const {},
  }) async {
    final payload = <String, dynamic>{
      'feature': feature.value,
      'params': params,
    };
    final body = await _post('/api/v1/run', payload, token: accessToken);
    return _dataMap(body);
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    String? captcha,
    bool? rememberMe,
  }) async {
    final payload = <String, dynamic>{
      'username': username,
      'password': password,
    };
    if (captcha != null && captcha.isNotEmpty) {
      payload['captcha'] = captcha;
    }
    if (rememberMe != null) {
      payload['rememberMe'] = rememberMe;
    }
    final body = await _post('/api/v1/auth/login', payload);
    return _dataMap(body);
  }

  Future<Map<String, dynamic>> session(String accessToken) async {
    final body = await _get('/api/v1/auth/session', token: accessToken);
    return _dataMap(body);
  }

  Future<Map<String, dynamic>> refresh(String accessToken) async {
    final body = await _post('/api/v1/auth/refresh', {
      'accessToken': accessToken,
    }, token: accessToken);
    return _dataMap(body);
  }

  Future<void> logout(String accessToken) async {
    await _post('/api/v1/auth/logout', const {}, token: accessToken);
  }

  Future<Map<String, dynamic>> wechatStart({
    String? apiBaseUrl,
    String? serviceUrl,
  }) async {
    final payload = <String, dynamic>{};
    if (apiBaseUrl != null && apiBaseUrl.isNotEmpty) {
      payload['apiBaseUrl'] = apiBaseUrl;
    }
    if (serviceUrl != null && serviceUrl.isNotEmpty) {
      payload['serviceUrl'] = serviceUrl;
    }
    final body = await _post('/api/v1/auth/wechat/start', payload);
    return _dataMap(body);
  }

  Future<Map<String, dynamic>> wechatStatus(String state) async {
    final body = await _get(
      '/api/v1/auth/wechat/status',
      queryParameters: {'state': state},
    );
    return _dataMap(body);
  }

  Future<Map<String, dynamic>> wechatComplete({
    required String state,
    String? redirectUrl,
    String? ticket,
  }) async {
    final payload = <String, dynamic>{'state': state};
    if (ticket != null && ticket.isNotEmpty) {
      payload['ticket'] = ticket;
    } else if (redirectUrl != null && redirectUrl.isNotEmpty) {
      payload['redirectUrl'] = redirectUrl;
    }
    final body = await _post('/api/v1/auth/wechat/complete', payload);
    return _dataMap(body);
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    String? token,
    Map<String, dynamic>? queryParameters,
  }) async {
    final Response<Object?> response;
    try {
      response = await _dio.get<Object?>(
        path,
        queryParameters: queryParameters,
        options: _options(token),
      );
    } on DioException catch (error) {
      throw XjitApiException(_dioErrorMessage(error));
    }
    return _bodyMap(response);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload, {
    String? token,
  }) async {
    final Response<Object?> response;
    try {
      response = await _dio.post<Object?>(
        path,
        data: payload,
        options: _options(token),
      );
    } on DioException catch (error) {
      throw XjitApiException(_dioErrorMessage(error));
    }
    return _bodyMap(response);
  }

  Options? _options(String? token) {
    final cleanToken = token?.trim();
    if (cleanToken == null || cleanToken.isEmpty) {
      return null;
    }
    return Options(headers: {'Authorization': 'Bearer $cleanToken'});
  }

  Map<String, dynamic> _bodyMap(Response<Object?> response) {
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
    return body;
  }

  Map<String, dynamic> _dataMap(Map<String, dynamic> body) {
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
