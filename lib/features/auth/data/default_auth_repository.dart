import '../domain/auth_models.dart';
import '../domain/auth_repository.dart';
import 'auth_api.dart';
import 'session_store.dart';

class DefaultAuthRepository implements AuthRepository {
  DefaultAuthRepository({required this._api, required this._store});

  final AuthApi _api;
  final SessionStore _store;

  @override
  Future<AuthSession?> readSession() => _store.read();
  @override
  Future<void> saveSession(AuthSession session) => _store.write(session);
  @override
  Future<void> clearSession() => _store.clear();
  @override
  Future<AuthSession> signIn({
    required String username,
    required String password,
    String? captcha,
  }) => _api.signIn(username: username, password: password, captcha: captcha);
  @override
  Future<AuthSession> refresh(AuthSession session) => _api.refresh(session);
  @override
  Future<void> revoke(AuthSession session) => _api.revoke(session);
  @override
  Future<WechatChallenge> startWechat() => _api.startWechat();
  @override
  Future<WechatResult> checkWechat(WechatChallenge challenge) =>
      _api.checkWechat(challenge);
  @override
  Future<WechatResult> completeWechat(
    WechatChallenge challenge, {
    required String ticket,
  }) => _api.completeWechat(challenge, ticket: ticket);
}
