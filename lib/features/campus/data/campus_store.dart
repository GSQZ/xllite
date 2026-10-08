import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/campus_local_data.dart';

abstract interface class CampusStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecureCampusStorage implements CampusStorage {
  const SecureCampusStorage(this.storage);
  final FlutterSecureStorage storage;
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String? value) => value == null
      ? storage.delete(key: key)
      : storage.write(key: key, value: value);
}

/// Bounded, versioned snapshots, isolated by API origin and authenticated user.
/// Writes are serialized so parallel requests cannot erase each other's entries.
class CampusStore {
  CampusStore(this.storage, {DateTime Function()? now})
    : now = now ?? DateTime.now;
  final CampusStorage storage;
  final DateTime Function() now;
  Future<void> _writes = Future.value();
  final Map<String, Future<Map<String, dynamic>>> _loaded = {};

  String _key(String scope, String kind) =>
      'xinli.campus.v1.$kind.${base64Url.encode(utf8.encode(scope))}';

  Future<Map<String, dynamic>> _entries(String scope) =>
      _loaded.putIfAbsent(scope, () async {
        try {
          final value = await storage.read(_key(scope, 'cache'));
          if (value == null || value.length > 2000000) return {};
          return Map<String, dynamic>.from(jsonDecode(value) as Map);
        } catch (_) {
          return {};
        }
      });

  Future<CachedData<Map<String, dynamic>>?> read(
    String scope,
    String key,
    Duration maxAge,
  ) async {
    try {
      final entry = (await _entries(scope))[key] as Map?;
      if (entry == null) return null;
      final at = DateTime.parse(entry['at'] as String);
      final age = now().difference(at);
      if (age.isNegative || age > maxAge) return null;
      return CachedData(Map<String, dynamic>.from(entry['data'] as Map), at);
    } catch (_) {
      return null;
    }
  }

  Future<void> put(String scope, String key, Map<String, dynamic> data) =>
      _enqueue(() async {
        final entries = await _entries(scope);
        entries.remove(key);
        entries[key] = {'at': now().toUtc().toIso8601String(), 'data': data};
        while (entries.length > 32 || jsonEncode(entries).length > 2000000) {
          entries.remove(entries.keys.first);
        }
        await storage.write(_key(scope, 'cache'), jsonEncode(entries));
      });

  Future<void> clear(String scope) => _enqueue(() async {
    _loaded[scope] = Future.value({});
    await storage.write(_key(scope, 'cache'), null);
  });

  Future<String?> preference(String scope, String name) =>
      storage.read(_key(scope, 'pref.$name'));
  Future<void> setPreference(String scope, String name, String? value) =>
      _enqueue(() => storage.write(_key(scope, 'pref.$name'), value));

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.catchError((Object _) {});
    return next;
  }
}
