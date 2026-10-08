import 'auth_models.dart';

abstract interface class AuthRepository {
  Future<AuthSession?> readSession();
  Future<void> saveSession(AuthSession session);
  Future<void> clearSession();
  Future<AuthSession> signIn({
    required String username,
    required String password,
    String? captcha,
  });
  Future<AuthSession> refresh(AuthSession session);
  Future<void> revoke(AuthSession session);
  Future<WechatChallenge> startWechat();
  Future<WechatResult> checkWechat(WechatChallenge challenge);
  Future<WechatResult> completeWechat(
    WechatChallenge challenge, {
    required String ticket,
  });
}
