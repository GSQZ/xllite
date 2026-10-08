import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'application/auth_controller.dart';
import 'data/auth_api.dart';
import 'data/default_auth_repository.dart';
import 'data/session_store.dart';

export 'application/auth_controller.dart';
export 'domain/auth_models.dart';
export 'domain/auth_repository.dart';

/// Create once in the app's State, call restore(), then dispose with the app.
AuthController createAuthController() {
  const baseUrl = String.fromEnvironment(
    'XJIT_API_BASE_URL',
    defaultValue: 'https://xllite.sayqz.com',
  );
  final uri = Uri.parse(baseUrl);
  if (uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError('XJIT_API_BASE_URL must be an HTTPS origin');
  }
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 45),
      contentType: Headers.jsonContentType,
    ),
  );
  return AuthController(
    repository: DefaultAuthRepository(
      api: AuthApi(dio),
      store: SecureSessionStore(const FlutterSecureStorage()),
    ),
    onDispose: () => dio.close(force: true),
  );
}
