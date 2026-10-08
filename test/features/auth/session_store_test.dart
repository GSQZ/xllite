import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/auth/data/session_store.dart';
import 'package:xinli_lite/features/auth/domain/auth_models.dart';

class BrokenStorage extends FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      throw PlatformException(code: 'locked', message: 'private details');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  late SecureSessionStore store;
  final session = AuthSession(
    accessToken: 'private-token',
    username: '20260001',
    source: 'password',
    expiresAt: DateTime.utc(2026, 11, 8),
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    store = SecureSessionStore(storage);
  });

  test('session round trips using one versioned secure entry', () async {
    await store.write(session);
    final entries = await storage.readAll();
    expect(entries.keys, [SecureSessionStore.sessionKey]);
    final json = jsonDecode(entries.values.single) as Map;
    expect(json['schemaVersion'], 1);
    expect((json['session'] as Map).containsKey('password'), isFalse);
    final restored = await store.read();
    expect(restored?.accessToken, session.accessToken);
    expect(restored?.expiresAt, session.expiresAt);
    expect(restored?.username, session.username);
  });

  for (final raw in [
    'broken-json',
    '[]',
    '{"schemaVersion":2,"session":{}}',
    '{"schemaVersion":1,"session":{"accessToken":""}}',
    '{"schemaVersion":1,"session":{"accessToken":"t","expiresAt":"invalid"}}',
  ]) {
    test('invalid persisted data is removed: $raw', () async {
      FlutterSecureStorage.setMockInitialValues({
        SecureSessionStore.sessionKey: raw,
      });
      expect(await store.read(), isNull);
      expect(await storage.read(key: SecureSessionStore.sessionKey), isNull);
    });
  }

  test(
    'restoring removes legacy password and token but preserves unrelated preferences',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'cas_password': 'legacy-secret',
        'api_access_token': 'legacy-token',
        'other_preference': 'preserved',
      });
      expect(await store.read(), isNull);
      expect(await storage.readAll(), {'other_preference': 'preserved'});
    },
  );

  test('clear removes session and legacy credentials only', () async {
    await store.write(session);
    await storage.write(key: 'cas_password', value: 'legacy-secret');
    await storage.write(key: 'other_preference', value: 'preserved');
    await store.clear();
    expect(await storage.readAll(), {'other_preference': 'preserved'});
  });

  test(
    'keychain failures remain observable and hide native error details',
    () async {
      store = SecureSessionStore(BrokenStorage());
      await expectLater(
        store.read(),
        throwsA(
          isA<AuthFailure>()
              .having((e) => e.kind, 'kind', AuthFailureKind.storage)
              .having(
                (e) => e.message,
                'safe message',
                isNot(contains('private details')),
              ),
        ),
      );
    },
  );
}
