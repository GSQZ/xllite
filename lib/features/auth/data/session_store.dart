import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/auth_models.dart';

abstract interface class SessionStore {
  Future<AuthSession?> read();
  Future<void> write(AuthSession session);
  Future<void> clear();
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore(this._storage);

  static const sessionKey = 'xinli.auth.session.v1';
  static const _legacyKeys = [
    'cas_password',
    'cas_username',
    'api_access_token',
    'api_token_type',
    'api_auth_source',
    'api_token_expires_at_ms',
  ];
  final FlutterSecureStorage _storage;

  @override
  Future<AuthSession?> read() async {
    try {
      // The rebuilt app requires a new login for legacy installations.
      await _clearLegacy();
      final value = await _storage.read(key: sessionKey);
      if (value == null) return null;
      try {
        final decoded = jsonDecode(value);
        if (decoded is! Map<String, dynamic> ||
            decoded['schemaVersion'] != 1 ||
            decoded['session'] is! Map<String, dynamic>) {
          throw const FormatException();
        }
        return AuthSession.fromJson(
          decoded['session'] as Map<String, dynamic>,
          now: DateTime.now(),
        );
      } on FormatException {
        await _storage.delete(key: sessionKey);
        return null;
      } on AuthFailure {
        await _storage.delete(key: sessionKey);
        return null;
      }
    } catch (_) {
      throw const AuthFailure(AuthFailureKind.storage, '无法读取安全存储，请重试');
    }
  }

  @override
  Future<void> write(AuthSession session) async {
    try {
      await _storage.write(
        key: sessionKey,
        value: jsonEncode({'schemaVersion': 1, 'session': session.toJson()}),
      );
    } catch (_) {
      throw const AuthFailure(AuthFailureKind.storage, '无法保存登录状态，请重试');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: sessionKey);
      await _clearLegacy();
    } catch (_) {
      throw const AuthFailure(AuthFailureKind.storage, '无法清除本地登录信息，请重试退出');
    }
  }

  Future<void> _clearLegacy() async {
    for (final key in _legacyKeys) {
      await _storage.delete(key: key);
    }
  }
}
