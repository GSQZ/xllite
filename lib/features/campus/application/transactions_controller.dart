import 'package:flutter/foundation.dart';

import '../domain/campus_failure.dart';
import '../domain/campus_repository.dart';
import '../domain/campus_local_data.dart';
import '../domain/card_models.dart';
import '../domain/records.dart';

class TransactionsState {
  TransactionsState({
    List<CardTransaction> items = const [],
    this.isLoading = false,
    this.hasLoaded = false,
    this.hasMore = false,
    this.pageNo = 0,
    this.failure,
    this.updatedAt,
    this.fromCache = false,
  }) : items = List.unmodifiable(items);
  final List<CardTransaction> items;
  final bool isLoading, hasLoaded, hasMore;
  final int pageNo;
  final CampusFailure? failure;
  final DateTime? updatedAt;
  final bool fromCache;
}

class TransactionsController extends ChangeNotifier {
  TransactionsController(this.repository);
  final CampusRepository repository;
  TransactionsState _state = TransactionsState();
  TransactionsState get state => _state;
  TransactionQuery _query = const TransactionQuery();
  TransactionQuery get query => _query;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _pending;

  Future<void> load({TransactionQuery? query}) {
    if (_disposed) return Future.value();
    final changed = query != null;
    if (!changed && _pending != null) return _pending!;
    if (query != null) _query = query;
    return _fetch(1, clear: changed);
  }

  Future<void> loadMore() {
    if (_disposed) return Future.value();
    if (_pending != null) return _pending!;
    if (!state.hasLoaded || !state.hasMore) return Future.value();
    return _fetch(state.pageNo + 1);
  }

  Future<void> _fetch(int page, {bool clear = false}) {
    final generation = ++_generation;
    final query = _query;
    var old = clear ? TransactionsState() : state;
    _state = TransactionsState(
      items: old.items,
      isLoading: true,
      hasLoaded: old.hasLoaded,
      hasMore: old.hasMore,
      pageNo: old.pageNo,
      updatedAt: old.updatedAt,
      fromCache: old.fromCache,
    );
    final future = Future<void>(() async {
      if (_disposed || generation != _generation) return;
      final local = repository;
      if (page == 1 && !old.hasLoaded && local is CampusLocalData) {
        try {
          final cached = await (local as CampusLocalData)
              .readCached<TransactionPage>('newcard.transactions', key: query);
          if (_disposed || generation != _generation) return;
          if (cached != null && cached.data.pageNo == 1) {
            old = TransactionsState(
              items: cached.data.transactions,
              hasLoaded: true,
              hasMore: false,
              pageNo: 1,
              updatedAt: cached.updatedAt,
              fromCache: true,
            );
            _state = TransactionsState(
              items: old.items,
              hasLoaded: true,
              isLoading: true,
              updatedAt: old.updatedAt,
              fromCache: true,
            );
            notifyListeners();
          }
        } catch (_) {
          /* Query the server when local records are unavailable. */
        }
      }
      if (_disposed || generation != _generation) return;
      try {
        final result = await repository.transactions(query, pageNo: page);
        if (_disposed || generation != _generation) return;
        if (result.pageNo != page) invalidData();
        final items = page == 1 ? <CardTransaction>[] : [...old.items];
        final seen = {
          for (final item in items)
            if (item.journo.isNotEmpty) item.journo,
        };
        for (final item in result.transactions) {
          if (item.journo.isEmpty || seen.add(item.journo)) items.add(item);
        }
        _state = TransactionsState(
          items: items,
          hasLoaded: true,
          hasMore: result.mayHaveMore,
          pageNo: page,
          updatedAt: DateTime.now(),
        );
      } catch (error) {
        if (_disposed || generation != _generation) return;
        _state = TransactionsState(
          items: old.items,
          hasLoaded: old.hasLoaded,
          hasMore: old.hasMore,
          pageNo: old.pageNo,
          updatedAt: old.updatedAt,
          fromCache: old.fromCache,
          failure: campusFailure(error, 'newcard.transactions'),
        );
      }
      _pending = null;
      notifyListeners();
    });
    _pending = future;
    notifyListeners();
    return future;
  }

  void reset() {
    if (_disposed) return;
    _generation++;
    _pending = null;
    _query = const TransactionQuery();
    _state = TransactionsState();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
