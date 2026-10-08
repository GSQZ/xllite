import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/auth/auth.dart';

final now = DateTime.utc(2026, 10, 8, 10);
AuthSession session({String token = 'test-token', Duration? lifetime}) =>
    AuthSession(
      accessToken: token,
      username: '20260001',
      source: 'password',
      expiresAt: now.add(lifetime ?? const Duration(days: 30)),
    );

WechatChallenge challenge() => WechatChallenge(
  state: 'state-1',
  authUrl: Uri.parse('https://cas.xjit.edu.cn/cas/federatedRedirect'),
  serviceUrl: Uri.parse('https://superapp.xjit.edu.cn/pages/tab/index/index'),
  expiresAt: now.add(const Duration(minutes: 10)),
);

class FakeAuthRepository implements AuthRepository {
  AuthSession? stored;
  AuthSession result = session();
  AuthFailure? readError;
  AuthFailure? writeError;
  AuthFailure? clearError;
  AuthFailure? loginError;
  AuthFailure? refreshError;
  AuthFailure? pollError;
  Completer<AuthSession>? loginGate;
  Completer<AuthSession>? refreshGate;
  Completer<void>? writeGate;
  Completer<void>? revokeGate;
  Completer<WechatResult>? pollGate;
  int loginCalls = 0;
  int refreshCalls = 0;
  int clearCalls = 0;
  int writeCalls = 0;
  int pollCalls = 0;
  int completeCalls = 0;
  String? lastUsername;
  String? lastPassword;
  WechatResult wechatResult = const WechatResult(WechatStatus.pending);

  @override
  Future<AuthSession?> readSession() async {
    if (readError != null) throw readError!;
    return stored;
  }

  @override
  Future<void> saveSession(AuthSession session) async {
    writeCalls++;
    if (writeGate != null) await writeGate!.future;
    if (writeError != null) throw writeError!;
    stored = session;
  }

  @override
  Future<void> clearSession() async {
    clearCalls++;
    if (clearError != null) throw clearError!;
    stored = null;
  }

  @override
  Future<AuthSession> signIn({
    required String username,
    required String password,
    String? captcha,
  }) async {
    loginCalls++;
    lastUsername = username;
    lastPassword = password;
    if (loginError != null) throw loginError!;
    return loginGate != null ? await loginGate!.future : result;
  }

  @override
  Future<AuthSession> refresh(AuthSession session) async {
    refreshCalls++;
    if (refreshError != null) throw refreshError!;
    return refreshGate != null ? await refreshGate!.future : result;
  }

  @override
  Future<void> revoke(AuthSession session) async {
    if (revokeGate != null) await revokeGate!.future;
  }

  @override
  Future<WechatChallenge> startWechat() async => challenge();

  @override
  Future<WechatResult> checkWechat(WechatChallenge challenge) async {
    pollCalls++;
    if (pollError != null) throw pollError!;
    return pollGate != null ? await pollGate!.future : wechatResult;
  }

  @override
  Future<WechatResult> completeWechat(
    WechatChallenge challenge, {
    required String ticket,
  }) async {
    completeCalls++;
    return wechatResult;
  }
}

void main() {
  late FakeAuthRepository repo;
  late AuthController controller;
  setUp(() {
    repo = FakeAuthRepository();
    controller = AuthController(repository: repo, now: () => now);
  });
  tearDown(() => controller.dispose());

  test('empty storage restores signed out without a remote request', () async {
    await controller.restore();
    expect(controller.state.phase, AuthPhase.signedOut);
    expect(repo.refreshCalls, 0);
  });

  test('valid stored session restores without network', () async {
    repo.stored = session();
    await controller.restore();
    expect(controller.state.isAuthenticated, isTrue);
    expect(repo.refreshCalls, 0);
  });

  test('invalid input is rejected before sending credentials', () async {
    await controller.signIn(username: '  ', password: 'x');
    expect(controller.state.failure?.kind, AuthFailureKind.validation);
    expect(controller.state.failure?.operation, AuthOperation.signIn);
    expect(repo.loginCalls, 0);
  });

  test(
    'login trims username, preserves password and suppresses duplicate submit',
    () async {
      repo.loginGate = Completer();
      final first = controller.signIn(
        username: ' 20260001 ',
        password: ' secret ',
      );
      await controller.signIn(username: 'other', password: 'second');
      expect(controller.state.phase, AuthPhase.signingIn);
      expect(repo.loginCalls, 1);
      expect(repo.lastUsername, '20260001');
      expect(repo.lastPassword, ' secret ');
      repo.loginGate!.complete(session());
      await first;
      expect(controller.state.isAuthenticated, isTrue);
      expect(repo.stored?.accessToken, 'test-token');
    },
  );

  test('rejection is observable and allows retry', () async {
    repo.loginError = const AuthFailure(AuthFailureKind.rejected, '登录未通过');
    await controller.signIn(username: 'student', password: 'wrong');
    expect(controller.state.phase, AuthPhase.signedOut);
    expect(controller.state.failure?.kind, AuthFailureKind.rejected);
    repo.loginError = null;
    await controller.signIn(username: 'student', password: 'correct');
    expect(controller.state.isAuthenticated, isTrue);
  });

  test('failed persistence does not report a successful login', () async {
    repo.writeError = const AuthFailure(AuthFailureKind.storage, '无法保存');
    await controller.signIn(username: 'student', password: 'secret');
    expect(controller.state.phase, AuthPhase.signedOut);
    expect(controller.state.failure?.kind, AuthFailureKind.storage);
  });

  test('startup rotates expiring token and persists new session', () async {
    repo.stored = session(lifetime: const Duration(minutes: 1));
    repo.result = session(token: 'new-token');
    await controller.restore();
    expect(repo.refreshCalls, 1);
    expect(repo.stored?.accessToken, 'new-token');
  });

  test(
    'network failure retains unexpired session and saved credentials',
    () async {
      repo.stored = session(lifetime: const Duration(minutes: 1));
      repo.refreshError = const AuthFailure(AuthFailureKind.network, '网络不可用');
      await controller.restore();
      expect(controller.state.isAuthenticated, isTrue);
      expect(controller.state.failure?.kind, AuthFailureKind.network);
      expect(controller.state.failure?.operation, AuthOperation.restore);
      expect(repo.clearCalls, 0);
    },
  );

  test(
    'expired offline session is retained for recovery but cannot authenticate',
    () async {
      repo.stored = session(lifetime: const Duration(seconds: -1));
      repo.refreshError = const AuthFailure(AuthFailureKind.network, '网络不可用');
      await controller.restore();
      expect(controller.state.isAuthenticated, isFalse);
      expect(repo.stored, isNotNull);
      repo.refreshError = null;
      await controller.restore();
      expect(controller.state.isAuthenticated, isTrue);
    },
  );

  test('confirmed unauthorized refresh clears credentials', () async {
    repo.stored = session(lifetime: const Duration(minutes: 1));
    repo.refreshError = const AuthFailure(AuthFailureKind.unauthorized, '已失效');
    await controller.restore();
    expect(controller.state.phase, AuthPhase.signedOut);
    expect(repo.stored, isNull);
  });

  test(
    'unknown expiry cannot restore offline as an authenticated session',
    () async {
      repo.stored = const AuthSession(
        accessToken: 'unknown-lifetime',
        username: 'student',
        source: 'password',
        expiresAt: null,
      );
      repo.refreshError = const AuthFailure(AuthFailureKind.network, '网络不可用');
      await controller.restore();
      expect(controller.state.isAuthenticated, isFalse);
      expect(repo.stored, isNotNull);
    },
  );

  test('rotated token remains current if persistence fails', () async {
    repo.stored = session();
    await controller.restore();
    repo.result = session(token: 'rotated-token');
    repo.writeError = const AuthFailure(AuthFailureKind.storage, '无法保存');
    await controller.refreshSession(force: true);
    expect(controller.state.session?.accessToken, 'rotated-token');
    expect(controller.state.failure?.kind, AuthFailureKind.storage);
    expect(controller.state.isRefreshing, isFalse);
  });

  test('late rotation cannot recreate session after logout', () async {
    repo.stored = session();
    await controller.restore();
    repo.refreshGate = Completer();
    final refresh = controller.refreshSession(force: true);
    await controller.signOut();
    repo.refreshGate!.complete(session(token: 'rotated-token'));
    await refresh;
    expect(controller.state.phase, AuthPhase.signedOut);
    expect(repo.stored, isNull);
  });

  test('concurrent refresh requests share a single rotation', () async {
    repo.stored = session();
    await controller.restore();
    repo.refreshGate = Completer();
    final first = controller.refreshSession(force: true);
    final second = controller.refreshSession(force: true);
    expect(identical(first, second), isTrue);
    expect(repo.refreshCalls, 1);
    repo.refreshGate!.complete(session(token: 'rotated'));
    await Future.wait([first, second]);
    expect(controller.state.session?.accessToken, 'rotated');
  });

  test('logout wins over late login response', () async {
    repo.loginGate = Completer();
    final login = controller.signIn(username: 'student', password: 'secret');
    await controller.signOut();
    repo.loginGate!.complete(session());
    await login;
    expect(controller.state.phase, AuthPhase.signedOut);
    expect(repo.stored, isNull);
    expect(repo.writeCalls, 0);
  });

  test(
    'logout clears credentials after an already pending storage write',
    () async {
      repo.writeGate = Completer();
      final login = controller.signIn(username: 'student', password: 'secret');
      await Future<void>.delayed(Duration.zero);
      expect(repo.writeCalls, 1);
      final logout = controller.signOut();
      repo.writeGate!.complete();
      await Future.wait([login, logout]);
      expect(repo.stored, isNull);
      expect(controller.state.phase, AuthPhase.signedOut);
    },
  );

  test(
    'local logout completes without waiting for server revocation',
    () async {
      repo.stored = session();
      repo.revokeGate = Completer();
      await controller.restore();
      await controller.signOut();
      expect(controller.state.phase, AuthPhase.signedOut);
      expect(repo.stored, isNull);
      repo.revokeGate!.complete();
    },
  );

  test('logout storage failure is visible and retryable', () async {
    repo.stored = session();
    await controller.restore();
    repo.clearError = const AuthFailure(AuthFailureKind.storage, '无法清除');
    await controller.signOut();
    expect(controller.state.failure?.kind, AuthFailureKind.storage);
    expect(controller.state.failure?.operation, AuthOperation.signOut);
    repo.clearError = null;
    await controller.signOut();
    expect(repo.stored, isNull);
  });

  test('only a matching WeChat callback exchanges a ticket', () async {
    await controller.startWechat();
    expect(
      await controller.handleWechatRedirect(
        'https://evil.example/?xjitApiState=state-1&ticket=secret',
      ),
      isFalse,
    );
    expect(
      await controller.handleWechatRedirect(
        'https://superapp.xjit.edu.cn/pages/tab/index/index?xjitApiState=wrong&ticket=secret',
      ),
      isFalse,
    );
    expect(repo.completeCalls, 0);
    repo.wechatResult = WechatResult(WechatStatus.success, session: session());
    expect(
      await controller.handleWechatRedirect(
        'https://superapp.xjit.edu.cn/pages/tab/index/index?xjitApiState=state-1&ticket=secret',
      ),
      isTrue,
    );
    expect(controller.state.isAuthenticated, isTrue);
  });

  testWidgets('polls never overlap and cancelled results cannot log in', (
    tester,
  ) async {
    repo.pollGate = Completer();
    await controller.startWechat();
    await tester.pump(const Duration(seconds: 2));
    expect(repo.pollCalls, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(repo.pollCalls, 1);
    controller.cancelWechat();
    repo.pollGate!.complete(
      WechatResult(WechatStatus.success, session: session()),
    );
    await tester.pump();
    expect(controller.state.phase, AuthPhase.signedOut);
    expect(repo.writeCalls, 0);
  });

  testWidgets(
    'poll failures retry and expiration is visible even during a slow request',
    (tester) async {
      repo.pollError = const AuthFailure(AuthFailureKind.network, '网络不可用');
      await controller.startWechat();
      await tester.pump(const Duration(seconds: 2));
      expect(controller.state.failure?.kind, AuthFailureKind.network);
      repo.pollError = null;
      repo.pollGate = Completer();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(minutes: 11));
      expect(controller.state.failure?.kind, AuthFailureKind.expired);
      repo.pollGate!.complete(
        WechatResult(WechatStatus.success, session: session()),
      );
      await tester.pump();
      expect(controller.state.isAuthenticated, isFalse);
    },
  );
}
