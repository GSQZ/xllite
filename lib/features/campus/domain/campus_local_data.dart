class CachedData<T> {
  const CachedData(this.data, this.updatedAt);
  final T data;
  final DateTime updatedAt;
}

/// Optional local capabilities. Account selection belongs to the repository,
/// never to a page; credentials and payment payloads are not cached.
abstract interface class CampusLocalData {
  Future<CachedData<T>?> readCached<T>(String operation, {Object? key});
  Future<String?> readPreference(String key);
  Future<void> writePreference(String key, String? value);
  Future<void> clearCache();
}
