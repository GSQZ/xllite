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
    required this.password,
  });

  final String username;
  final String password;
}

class AuthController extends AsyncNotifier<AuthSession?> {
  static const _usernameKey = 'cas_username';
  static const _passwordKey = 'cas_password';

  @override
  Future<AuthSession?> build() async {
    final storage = ref.watch(secureStorageProvider);
    final username = await storage.read(key: _usernameKey);
    final password = await storage.read(key: _passwordKey);

    if (username == null ||
        username.trim().isEmpty ||
        password == null ||
        password.isEmpty) {
      return null;
    }

    return AuthSession(username: username, password: password);
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
    state = await AsyncValue.guard(() async {
      final api = ref.read(xjitApiClientProvider);
      final profile = await api.run(
        XjitFeature.profile,
        username: cleanUsername,
        password: password,
      );
      final hasProfile =
          _hasText(profile['studentId']) || _hasText(profile['name']);
      if (!hasProfile) {
        throw const XjitApiException('登录未返回有效学生信息，请检查账号密码');
      }

      final storage = ref.read(secureStorageProvider);
      await storage.write(key: _usernameKey, value: cleanUsername);
      await storage.write(key: _passwordKey, value: password);
      return AuthSession(username: cleanUsername, password: password);
    });
  }

  Future<void> signOut() async {
    final storage = ref.read(secureStorageProvider);
    await storage.delete(key: _usernameKey);
    await storage.delete(key: _passwordKey);
    state = const AsyncData(null);
  }

  bool _hasText(Object? value) {
    return value != null && value.toString().trim().isNotEmpty;
  }
}
