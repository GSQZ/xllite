import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/campus_failure.dart';
import '../domain/campus_repository.dart';
import '../domain/card_models.dart';
import 'resource_controller.dart';

/// A spendable credential lives only while its page is visible and foreground.
/// Call setVisible for route/tab changes and setForeground for app lifecycle.
class CampusCodeController extends ChangeNotifier {
  CampusCodeController(this.repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _resource.addListener(notifyListeners);
  }
  final CampusRepository repository;
  final DateTime Function() _now;
  final _resource = ResourceController<CampusCode>(
    'newcard.campus_code.qrcode',
  );
  ResourceState<CampusCode> get state => _resource.state;
  CampusCode? get usableCode {
    final code = state.data;
    return _visible && _foreground && code != null && !code.isExpired(_now())
        ? code
        : null;
  }

  bool _visible = false, _foreground = true, _disposed = false;
  int _generation = 0;
  Timer? _expiry;
  Future<void>? _pending;

  Future<void> setVisible(bool visible) {
    if (_disposed) return Future.value();
    _visible = visible;
    if (!visible) {
      _clear();
      return Future.value();
    }
    return refresh();
  }

  Future<void> setForeground(bool foreground) {
    if (_disposed) return Future.value();
    _foreground = foreground;
    if (!foreground) {
      _clear();
      return Future.value();
    }
    return refresh();
  }

  Future<void> refresh() {
    if (_disposed || !_visible || !_foreground) return Future.value();
    if (_pending != null) return _pending!;
    final generation = ++_generation;
    _expiry?.cancel();
    _resource.reset();
    final future = _resource
        .load(() async {
          final code = await repository.campusCode();
          if (code.isExpired(_now())) {
            throw const CampusFailure(
              CampusFailureKind.rejected,
              '付款码已过期，请重新获取',
            );
          }
          return code;
        })
        .then((_) {
          if (_disposed || generation != _generation) return;
          _pending = null;
          final code = usableCode;
          if (code != null) {
            _expiry = Timer(
              code.expiresAt.difference(_now()),
              () => unawaited(refresh()),
            );
          }
        });
    _pending = future;
    return future;
  }

  void _clear() {
    _generation++;
    _pending = null;
    _expiry?.cancel();
    _resource.reset();
  }

  void resetSession() {
    if (_disposed) return;
    _visible = false;
    _clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _expiry?.cancel();
    _resource.removeListener(notifyListeners);
    _resource.dispose();
    super.dispose();
  }
}
