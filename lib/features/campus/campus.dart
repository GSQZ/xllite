import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/auth.dart';
import 'application/campus_controller.dart';
import 'data/campus_api.dart';
import 'data/default_campus_repository.dart';
import 'data/campus_store.dart';

export 'application/campus_controller.dart';
export 'application/campus_code_controller.dart';
export 'application/home_controller.dart';
export 'application/payment_controller.dart';
export 'application/resource_controller.dart';
export 'application/transactions_controller.dart';
export 'domain/academic_models.dart';
export 'domain/campus_failure.dart';
export 'domain/campus_repository.dart';
export 'domain/campus_local_data.dart';
export 'domain/card_models.dart';
export 'domain/records.dart';
export 'domain/schedule_planner.dart';

/// Create once next to AuthController; dispose this before disposing auth.
CampusController createCampusController(AuthController auth) {
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
      contentType: Headers.jsonContentType,
      connectTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 45),
    ),
  );
  return CampusController(
    auth: auth,
    repository: DefaultCampusRepository(
      CampusApi(dio, AuthCampusSession(auth)),
      store: CampusStore(const SecureCampusStorage(FlutterSecureStorage())),
      account: () =>
          auth.state.isAuthenticated ? auth.state.session?.username : null,
    ),
    onDispose: () => dio.close(force: true),
  );
}
