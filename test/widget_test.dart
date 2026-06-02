import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/core/config/app_config.dart';

void main() {
  test('app config exposes product identity', () {
    expect(AppConfig.appName, '新理Lite');
    expect(AppConfig.apiBaseUrl, startsWith('http://103.236.73.149:8765'));
  });
}
