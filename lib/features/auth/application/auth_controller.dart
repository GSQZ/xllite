import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/auth_models.dart';
import '../domain/auth_repository.dart';

/// UI-independent authentication state. The app owns one instance and disposes it.
class AuthController extends ChangeNotifier {
  AuthController({
    required this._repository,
    DateTime Function()? now,
    this.pollInterval = const Duration(seconds: 2),
    this._onDispose,
  }) : _now = now ?? DateTime.now;

  final AuthRepository _repository;
  final DateTime Function() _now;
  final VoidCallback? _onDispose;
  final Duration pollInterval;
  AuthState _state = const AuthState();
  AuthState get state => _state;

  /// Changes across login/logout attempts, but not token rotation. Business
  /// requests use this to discard results from a previous login, even same user.
  int get sessionRevision => _generation;
  Timer? _pollTimer;
  Timer? _expiryTimer;
  Future<void>? _refreshFuture;
  Future<void> _storageQueue = Future.value();
  int _generation = 0;
  bool _disposed = false;

  bool _current(int generation) => !_disposed && generation == _generation;

  void _emit(AuthState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  int _begin() {
    _stopWechatTimers();
    return ++_generation;
  }

  void _stopWechatTimers() {
    _pollTimer?.cancel();
    _expiryTimer?.cancel();
  }

  /// Call once at app startup, or retry after a local storage error.
  Future<void> restore() async {
    if (_disposed || _state.isBusy || _state.isAuthenticated) return;
    final generation = _begin();
    _emit(const AuthState(phase: AuthPhase.restoring));
    AuthSession? saved;
    try {
      saved = await _repository.readSession();
      if (!_current(generation)) return;
      if (saved == null) {
        _emit(const AuthState(phase: AuthPhase.signedOut));
        return;
      }
      if (saved.needsRefresh(_now())) {
        final fresh = await _repository.refresh(saved);
        // Rotation invalidates the old token even if the following disk write
        // fails. Retain the newly issued token for this running app.
        saved = fresh;
        await _accept(fresh, generation);
      } else {
        _emit(AuthState(phase: AuthPhase.authenticated, session: saved));
      }
    } catch (error) {
      if (!_current(generation)) return;
      await _handleSessionError(
        error,
        saved,
        generation,
        AuthOperation.restore,
      );
    }
  }

  /// Password is sent as entered and never stored in state or persistent storage.
  /// Errors are exposed in state.failure, not thrown to widget callbacks.
  Future<void> signIn({
    required String username,
    required String password,
    String? captcha,
  }) async {
    if (_disposed || _state.isBusy || _state.isAuthenticated) return;
    final generation = _begin();
    final cleanUsername = username.trim();
    if (cleanUsername.isEmpty || password.isEmpty) {
      _emit(
        const AuthState(
          phase: AuthPhase.signedOut,
          failure: AuthFailure(
            AuthFailureKind.validation,
            '请输入学号和 CAS 密码',
            operation: AuthOperation.signIn,
          ),
        ),
      );
      return;
    }
    _emit(const AuthState(phase: AuthPhase.signingIn));
    try {
      final session = await _repository.signIn(
        username: cleanUsername,
        password: password,
        captcha: captcha,
      );
      await _accept(session, generation);
    } catch (error) {
      if (_current(generation)) {
        _emit(
          AuthState(
            phase: AuthPhase.signedOut,
            failure: _failure(error, AuthOperation.signIn),
          ),
        );
      }
    }
  }

  /// Concurrent callers share one token rotation. No business request is replayed.
  /// Call on app resume or before protected requests; force after a confirmed 401.
  Future<void> refreshSession({bool force = false}) {
    if (_disposed) return Future.value();
    final existing = _refreshFuture;
    if (existing != null) return existing;
    final session = _state.session;
    if (!_state.isAuthenticated || session == null || _state.isBusy) {
      return Future.value();
    }
    if (!force && !session.needsRefresh(_now())) return Future.value();
    late final Future<void> future;
    future = _refresh(session).whenComplete(() {
      if (identical(_refreshFuture, future)) _refreshFuture = null;
    });
    _refreshFuture = future;
    return future;
  }

  Future<void> _refresh(AuthSession session) async {
    final generation = _generation;
    var latest = session;
    _emit(
      AuthState(
        phase: AuthPhase.authenticated,
        session: session,
        isRefreshing: true,
      ),
    );
    try {
      final fresh = await _repository.refresh(session);
      latest = fresh;
      await _accept(fresh, generation);
    } catch (error) {
      if (_current(generation)) {
        await _handleSessionError(
          error,
          latest,
          generation,
          AuthOperation.refresh,
        );
      }
    }
  }

  Future<void> _handleSessionError(
    Object error,
    AuthSession? saved,
    int generation,
    AuthOperation operation,
  ) async {
    var failure = _failure(error, operation);
    if (failure.kind == AuthFailureKind.unauthorized) {
      try {
        await _queueStorage(() => _repository.clearSession());
      } catch (error) {
        failure = _failure(error, operation);
      }
      if (_current(generation)) {
        _emit(AuthState(phase: AuthPhase.signedOut, failure: failure));
      }
      return;
    }
    // Keep saved credentials on transient failures. Expired sessions must not
    // grant access, but restore() can retry them when the network returns.
    if (_current(generation)) {
      final usable =
          saved != null && saved.expiresAt != null && !saved.isExpired(_now());
      _emit(
        AuthState(
          phase: usable ? AuthPhase.authenticated : AuthPhase.signedOut,
          session: usable ? saved : null,
          failure: failure,
        ),
      );
    }
  }

  Future<void> signOut() async {
    if (_disposed || _state.phase == AuthPhase.signingOut) return;
    final previous = _state.session;
    final generation = _begin();
    _emit(const AuthState(phase: AuthPhase.signingOut));
    try {
      // Local logout never waits for a slow or unreachable server.
      await _queueStorage(() => _repository.clearSession());
      if (!_current(generation)) return;
      _emit(const AuthState(phase: AuthPhase.signedOut));
      if (previous != null) unawaited(_revokeQuietly(previous));
    } catch (error) {
      if (_current(generation)) {
        _emit(
          AuthState(
            phase: AuthPhase.signedOut,
            failure: _failure(error, AuthOperation.signOut),
          ),
        );
      }
    }
  }

  /// A protected request still received 401 after renewal. A late response from
  /// an older token must never sign out a newer session.
  Future<void> invalidateSession(String rejectedToken) async {
    if (_disposed ||
        !_state.isAuthenticated ||
        _state.session?.accessToken != rejectedToken) {
      return;
    }
    final generation = _begin();
    _emit(
      const AuthState(
        phase: AuthPhase.signedOut,
        failure: AuthFailure(
          AuthFailureKind.unauthorized,
          '登录已失效，请重新登录',
          operation: AuthOperation.refresh,
        ),
      ),
    );
    try {
      await _queueStorage(() => _repository.clearSession());
    } catch (error) {
      if (_current(generation)) {
        _emit(
          AuthState(
            phase: AuthPhase.signedOut,
            failure: _failure(error, AuthOperation.signOut),
          ),
        );
      }
    }
  }

  Future<void> _revokeQuietly(AuthSession session) async {
    try {
      await _repository.revoke(session);
    } catch (_) {
      // Local credentials have already been removed. Do not restore the session.
    }
  }

  Future<void> startWechat() async {
    if (_disposed || _state.isBusy || _state.isAuthenticated) return;
    final generation = _begin();
    _emit(const AuthState(phase: AuthPhase.wechatStarting));
    try {
      final challenge = await _repository.startWechat();
      if (!_current(generation)) return;
      _emit(AuthState(phase: AuthPhase.wechatPending, challenge: challenge));
      _watchChallenge(challenge, generation);
    } catch (error) {
      if (_current(generation)) {
        _emit(
          AuthState(
            phase: AuthPhase.signedOut,
            failure: _failure(error, AuthOperation.wechat),
          ),
        );
      }
    }
  }

  /// Returns false for unrelated navigation. A true result must be blocked in
  /// the WebView: the controller exchanges the ticket with the backend.
  Future<bool> handleWechatRedirect(String url) async {
    final challenge = _state.challenge;
    if (_disposed || challenge == null) return false;
    final ticket = challenge.ticketFromRedirect(url);
    if (ticket == null) return false;
    if (_state.phase != AuthPhase.wechatPending) return true;
    if (!_now().isBefore(challenge.expiresAt)) {
      _expireWechat();
      return true;
    }
    // Invalidates any in-flight poll before starting completion.
    final generation = _begin();
    _emit(AuthState(phase: AuthPhase.wechatCompleting, challenge: challenge));
    _armExpiry(challenge, generation);
    try {
      final result = await _repository.completeWechat(
        challenge,
        ticket: ticket,
      );
      await _applyWechatResult(result, challenge, generation);
    } catch (error) {
      if (_current(generation)) {
        _emit(
          AuthState(
            phase: AuthPhase.wechatPending,
            challenge: challenge,
            failure: _failure(error, AuthOperation.wechat),
          ),
        );
        _watchChallenge(challenge, generation);
      }
    }
    return true;
  }

  void cancelWechat() {
    if (_disposed ||
        !const {
          AuthPhase.wechatStarting,
          AuthPhase.wechatPending,
          AuthPhase.wechatCompleting,
        }.contains(_state.phase)) {
      return;
    }
    _begin();
    _emit(const AuthState(phase: AuthPhase.signedOut));
  }

  void clearFailure() {
    if (_disposed || _state.failure == null) return;
    _emit(
      AuthState(
        phase: _state.phase,
        session: _state.session,
        challenge: _state.challenge,
        isRefreshing: _state.isRefreshing,
      ),
    );
  }

  void _watchChallenge(WechatChallenge challenge, int generation) {
    if (!_current(generation)) return;
    if (!_now().isBefore(challenge.expiresAt)) {
      _expireWechat();
      return;
    }
    _armExpiry(challenge, generation);
    _pollTimer?.cancel();
    _pollTimer = Timer(pollInterval, () => _poll(challenge, generation));
  }

  void _armExpiry(WechatChallenge challenge, int generation) {
    _expiryTimer?.cancel();
    _expiryTimer = Timer(challenge.expiresAt.difference(_now()), () {
      if (_current(generation)) _expireWechat();
    });
  }

  void _expireWechat() {
    _begin();
    _emit(
      const AuthState(
        phase: AuthPhase.signedOut,
        failure: AuthFailure(
          AuthFailureKind.expired,
          '二维码已过期，请重新获取',
          operation: AuthOperation.wechat,
        ),
      ),
    );
  }

  Future<void> _poll(WechatChallenge challenge, int generation) async {
    if (!_current(generation)) return;
    try {
      final result = await _repository.checkWechat(challenge);
      await _applyWechatResult(result, challenge, generation);
    } catch (error) {
      if (!_current(generation)) return;
      final failure = _failure(error, AuthOperation.wechat);
      if (failure.kind == AuthFailureKind.network ||
          failure.kind == AuthFailureKind.server) {
        _emit(
          AuthState(
            phase: AuthPhase.wechatPending,
            challenge: challenge,
            failure: failure,
          ),
        );
        _watchChallenge(challenge, generation);
      } else {
        _begin();
        _emit(AuthState(phase: AuthPhase.signedOut, failure: failure));
      }
    }
  }

  Future<void> _applyWechatResult(
    WechatResult result,
    WechatChallenge challenge,
    int generation,
  ) async {
    if (!_current(generation)) return;
    switch (result.status) {
      case WechatStatus.pending:
        _emit(AuthState(phase: AuthPhase.wechatPending, challenge: challenge));
        _watchChallenge(challenge, generation);
      case WechatStatus.success:
        final session = result.session;
        if (session == null) {
          throw const AuthFailure(AuthFailureKind.invalidResponse, '扫码未返回登录信息');
        }
        await _accept(session, generation);
      case WechatStatus.expired:
        _expireWechat();
      case WechatStatus.error:
        _begin();
        _emit(
          const AuthState(
            phase: AuthPhase.signedOut,
            failure: AuthFailure(
              AuthFailureKind.rejected,
              '扫码登录失败，请重新获取二维码',
              operation: AuthOperation.wechat,
            ),
          ),
        );
    }
  }

  Future<void> _accept(AuthSession session, int generation) async {
    if (!_current(generation)) return;
    if (session.accessToken.isEmpty || session.isExpired(_now())) {
      throw const AuthFailure(AuthFailureKind.invalidResponse, '登录信息已过期，请重试');
    }
    // Prevent late success from an expired/cancelled QR request while persisting.
    _stopWechatTimers();
    await _queueStorage(() async {
      if (_current(generation)) await _repository.saveSession(session);
    });
    if (!_current(generation)) return;
    _emit(AuthState(phase: AuthPhase.authenticated, session: session));
  }

  Future<void> _queueStorage(Future<void> Function() operation) {
    final result = _storageQueue.then((_) => operation());
    _storageQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  AuthFailure _failure(Object error, AuthOperation operation) =>
      error is AuthFailure
      ? AuthFailure(error.kind, error.message, operation: operation)
      : AuthFailure(
          AuthFailureKind.server,
          '操作未完成，请稍后重试',
          operation: operation,
        );

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _stopWechatTimers();
    _onDispose?.call();
    super.dispose();
  }
}
