import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/xjit_api_client.dart';
import '../api/xjit_features.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

class AuthSession {
  const AuthSession({
    required this.username,
    required this.accessToken,
    this.tokenType = 'Bearer',
    this.source = 'password',
    this.expiresAtMillis,
  });

  final String username;
  final String accessToken;
  final String tokenType;
  final String source;
  final int? expiresAtMillis;

  bool get isExpired {
    final expiresAt = expiresAtMillis;
    if (expiresAt == null) {
      return false;
    }
    return DateTime.now().millisecondsSinceEpoch >= expiresAt;
  }

  bool get needsRefresh {
    final expiresAt = expiresAtMillis;
    if (expiresAt == null) {
      return false;
    }
    const refreshAhead = Duration(minutes: 2);
    return DateTime.now().millisecondsSinceEpoch >=
        expiresAt - refreshAhead.inMilliseconds;
  }
}

class AuthController extends AsyncNotifier<AuthSession?> {
  static const _usernameKey = 'cas_username';
  static const _legacyPasswordKey = 'cas_password';
  static const _accessTokenKey = 'api_access_token';
  static const _tokenTypeKey = 'api_token_type';
  static const _sourceKey = 'api_auth_source';
  static const _expiresAtKey = 'api_token_expires_at_ms';

  @override
  Future<AuthSession?> build() async {
    final storage = ref.watch(secureStorageProvider);
    final session = await _readSession(storage);
    if (session != null) {
      if (!session.needsRefresh) {
        return session;
      }
      try {
        return await _refreshSession(session);
      } catch (_) {
        await _clearStoredSession(storage);
        return null;
      }
    }

    return _migrateLegacyPasswordLogin(storage);
  }

  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    final cleanUsername = username.trim();
    if (cleanUsername.isEmpty || password.isEmpty) {
      throw const XjitApiException('请输入学号和 CAS 密码');
    }

    state = const AsyncLoading();
    try {
      final data = await ref
          .read(xjitApiClientProvider)
          .login(username: cleanUsername, password: password);
      final session = await _resolveSessionUsername(
        _sessionFromData(data, fallbackUsername: cleanUsername),
      );
      await _saveSession(session);
      await ref.read(xjitApiCacheProvider).clear();
      state = AsyncData(session);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      await ref.read(secureStorageProvider).delete(key: _legacyPasswordKey);
    }
  }

  Future<void> signInWithWechatData(Map<String, dynamic> data) async {
    final session = await _resolveSessionUsername(
      _sessionFromData(data, fallbackSource: 'wechat'),
    );
    await _saveSession(session);
    await ref.read(xjitApiCacheProvider).clear();
    state = AsyncData(session);
  }

  Future<void> signInWithWechatComplete({
    required String state,
    String? redirectUrl,
    String? ticket,
  }) async {
    final data = await ref
        .read(xjitApiClientProvider)
        .wechatComplete(state: state, redirectUrl: redirectUrl, ticket: ticket);
    await signInWithWechatData(data);
  }

  Future<void> signOut() async {
    final storage = ref.read(secureStorageProvider);
    final current = state.when(
      data: (value) => value,
      error: (error, stackTrace) => null,
      loading: () => null,
    );
    if (current != null && current.accessToken.isNotEmpty) {
      try {
        await ref.read(xjitApiClientProvider).logout(current.accessToken);
      } catch (_) {
        // Local logout should work even if the server session is already gone.
      }
    }
    await _clearStoredSession(storage);
    await ref.read(xjitApiCacheProvider).clear();
    state = const AsyncData(null);
  }

  Future<AuthSession?> _migrateLegacyPasswordLogin(
    FlutterSecureStorage storage,
  ) async {
    final username = (await storage.read(key: _usernameKey))?.trim();
    final password = await storage.read(key: _legacyPasswordKey);
    if (!_hasText(username) || !_hasText(password)) {
      await storage.delete(key: _legacyPasswordKey);
      return null;
    }

    try {
      final data = await ref
          .read(xjitApiClientProvider)
          .login(username: username!, password: password!);
      final session = await _resolveSessionUsername(
        _sessionFromData(data, fallbackUsername: username),
      );
      await _saveSession(session);
      return session;
    } catch (_) {
      await _clearStoredSession(storage);
      return null;
    } finally {
      await storage.delete(key: _legacyPasswordKey);
    }
  }

  Future<AuthSession> _refreshSession(AuthSession session) async {
    final data = await ref
        .read(xjitApiClientProvider)
        .refresh(session.accessToken);
    final refreshed = _sessionFromData(
      data,
      fallbackUsername: session.username,
      fallbackSource: session.source,
    );
    await _saveSession(refreshed);
    return refreshed;
  }

  Future<AuthSession?> _readSession(FlutterSecureStorage storage) async {
    final accessToken = await storage.read(key: _accessTokenKey);
    if (!_hasText(accessToken)) {
      return null;
    }
    final username = (await storage.read(key: _usernameKey))?.trim();
    final expiresAt = int.tryParse(
      await storage.read(key: _expiresAtKey) ?? '',
    );
    return AuthSession(
      username: username ?? '',
      accessToken: accessToken!.trim(),
      tokenType: await storage.read(key: _tokenTypeKey) ?? 'Bearer',
      source: await storage.read(key: _sourceKey) ?? 'password',
      expiresAtMillis: expiresAt,
    );
  }

  AuthSession _sessionFromData(
    Map<String, dynamic> data, {
    String? fallbackUsername,
    String fallbackSource = 'password',
  }) {
    final accessToken = data['accessToken']?.toString().trim();
    if (!_hasText(accessToken)) {
      throw const XjitApiException('登录成功但没有返回 accessToken');
    }

    return AuthSession(
      username: _cleanText(data['username']) ?? fallbackUsername ?? '',
      accessToken: accessToken!,
      tokenType: _cleanText(data['tokenType']) ?? 'Bearer',
      source: _cleanText(data['source']) ?? fallbackSource,
      expiresAtMillis: _expiresAtMillis(data),
    );
  }

  Future<AuthSession> _resolveSessionUsername(AuthSession session) async {
    if (_hasText(session.username)) {
      return session;
    }

    try {
      final profile = await ref
          .read(xjitApiClientProvider)
          .run(XjitFeature.profile, accessToken: session.accessToken);
      final username =
          _cleanText(profile['studentId']) ??
          _cleanText(profile['idSerial']) ??
          '';
      if (!_hasText(username)) {
        return session;
      }
      return AuthSession(
        username: username,
        accessToken: session.accessToken,
        tokenType: session.tokenType,
        source: session.source,
        expiresAtMillis: session.expiresAtMillis,
      );
    } catch (_) {
      return session;
    }
  }

  int? _expiresAtMillis(Map<String, dynamic> data) {
    final rawExpiresAt = data['expiresAt'];
    final expiresAt = _toInt(rawExpiresAt);
    if (expiresAt != null) {
      return expiresAt > 100000000000 ? expiresAt : expiresAt * 1000;
    }

    final expiresInSeconds = _toInt(data['expiresInSeconds']);
    if (expiresInSeconds == null || expiresInSeconds <= 0) {
      return null;
    }
    return DateTime.now().millisecondsSinceEpoch + expiresInSeconds * 1000;
  }

  int? _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  String? _cleanText(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  Future<void> _saveSession(AuthSession session) async {
    final storage = ref.read(secureStorageProvider);
    await storage.write(key: _usernameKey, value: session.username);
    await storage.write(key: _accessTokenKey, value: session.accessToken);
    await storage.write(key: _tokenTypeKey, value: session.tokenType);
    await storage.write(key: _sourceKey, value: session.source);
    if (session.expiresAtMillis == null) {
      await storage.delete(key: _expiresAtKey);
    } else {
      await storage.write(
        key: _expiresAtKey,
        value: session.expiresAtMillis.toString(),
      );
    }
    await storage.delete(key: _legacyPasswordKey);
  }

  Future<void> _clearStoredSession(FlutterSecureStorage storage) async {
    await storage.delete(key: _usernameKey);
    await storage.delete(key: _legacyPasswordKey);
    await storage.delete(key: _accessTokenKey);
    await storage.delete(key: _tokenTypeKey);
    await storage.delete(key: _sourceKey);
    await storage.delete(key: _expiresAtKey);
  }

  bool _hasText(Object? value) {
    return value != null && value.toString().trim().isNotEmpty;
  }
}
