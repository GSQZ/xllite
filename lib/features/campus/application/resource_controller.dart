import 'package:flutter/foundation.dart';

import '../domain/campus_failure.dart';
import '../domain/campus_local_data.dart';

enum ResourcePhase { idle, loading, ready, failure }

class ResourceState<T> {
  const ResourceState({
    this.phase = ResourcePhase.idle,
    this.data,
    this.failure,
    this.updatedAt,
    this.key,
    this.fromCache = false,
  });
  final ResourcePhase phase;
  final T? data;
  final CampusFailure? failure;
  final DateTime? updatedAt;
  final Object? key;
  final bool fromCache;
  bool get isLoading => phase == ResourcePhase.loading;
  bool get isRefreshing => isLoading && data != null;
  bool get hasData => data != null;
  bool get isStale => data != null && failure != null;
}

/// Single resource, latest query wins. A refresh preserves visible data; changing
/// a query clears it. Empty success is represented by data, never by failure.
class ResourceController<T> extends ChangeNotifier {
  ResourceController(this.operation, {DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final String operation;
  final DateTime Function() _now;
  ResourceState<T> _state = const ResourceState();
  ResourceState<T> get state => _state;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _pending;
  Future<CachedData<T>?> Function(Object? key)? readCache;
  Duration freshness = const Duration(minutes: 5);

  void seed(ResourceState<T> source, {Object? key}) {
    if (_disposed ||
        _pending != null ||
        state.data != null ||
        source.data == null ||
        source.phase != ResourcePhase.ready) {
      return;
    }
    _state = ResourceState(
      phase: ResourcePhase.ready,
      data: source.data,
      updatedAt: source.updatedAt,
      key: key,
      fromCache: source.fromCache,
    );
    notifyListeners();
  }

  Future<void> load(
    Future<T> Function() fetch, {
    Object? key,
    bool refresh = false,
  }) {
    if (_disposed) return Future.value();
    if (state.key == key) {
      if (_pending != null) return _pending!;
      if (!refresh &&
          state.phase == ResourcePhase.ready &&
          state.updatedAt != null &&
          !_now().difference(state.updatedAt!).isNegative &&
          _now().difference(state.updatedAt!) < freshness) {
        return Future.value();
      }
    }
    final generation = ++_generation;
    var old = state.key == key ? state.data : null;
    var updated = state.key == key ? state.updatedAt : null;
    var cached = state.key == key && state.fromCache;
    _state = ResourceState(
      phase: ResourcePhase.loading,
      data: old,
      updatedAt: updated,
      key: key,
      fromCache: cached,
    );
    // Defer execution until the pending future is assigned (also for sync fakes).
    final future = Future<void>(() async {
      if (_disposed || generation != _generation) return;
      if (old == null && readCache != null) {
        try {
          final snapshot = await readCache!(key);
          if (_disposed || generation != _generation) return;
          if (snapshot != null) {
            old = snapshot.data;
            updated = snapshot.updatedAt;
            cached = true;
            _state = ResourceState(
              phase: ResourcePhase.loading,
              data: old,
              updatedAt: updated,
              key: key,
              fromCache: true,
            );
            notifyListeners();
          }
        } catch (_) {
          /* Cache failure must never prevent the network request. */
        }
      }
      if (_disposed || generation != _generation) return;
      try {
        final data = await fetch();
        if (_disposed || generation != _generation) return;
        _state = ResourceState(
          phase: ResourcePhase.ready,
          data: data,
          key: key,
          updatedAt: _now(),
        );
      } catch (error) {
        if (_disposed || generation != _generation) return;
        _state = ResourceState(
          phase: ResourcePhase.failure,
          data: old,
          key: key,
          updatedAt: updated,
          failure: campusFailure(error, operation),
          fromCache: cached,
        );
      }
      if (!_disposed && generation == _generation) {
        _pending = null;
        notifyListeners();
      }
    });
    _pending = future;
    notifyListeners();
    return future;
  }

  void reset() {
    if (_disposed) return;
    _generation++;
    _pending = null;
    _state = const ResourceState();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
