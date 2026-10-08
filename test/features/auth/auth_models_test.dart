import 'package:flutter_test/flutter_test.dart';
import 'package:xinli_lite/features/auth/auth.dart';

void main() {
  final now = DateTime.utc(2026, 10, 8);
  test(
    'seconds and milliseconds absolute expiry take priority over relative expiry',
    () {
      final expires = now.add(const Duration(days: 30));
      for (final timestamp in [
        expires.millisecondsSinceEpoch,
        expires.millisecondsSinceEpoch ~/ 1000,
      ]) {
        final session = AuthSession.fromJson({
          'accessToken': 'token',
          'expiresAt': timestamp,
          'expiresInSeconds': 1,
        }, now: now);
        expect(session.expiresAt, expires);
        expect(session.needsRefresh(now), isFalse);
        expect(session.isExpired(expires), isTrue);
      }
    },
  );

  test(
    'unknown lifetime requires refresh and never guesses a 30-day expiry',
    () {
      final session = AuthSession.fromJson({'accessToken': 'token'}, now: now);
      expect(session.expiresAt, isNull);
      expect(session.needsRefresh(now), isTrue);
    },
  );

  final valid = {
    'state': 'state-1',
    'authUrl': 'https://cas.xjit.edu.cn/cas/federatedRedirect',
    'serviceUrl':
        'https://superapp.xjit.edu.cn/pages/tab/index/index?xjitApiState=state-1',
    'expiresInSeconds': 600,
  };

  test(
    'challenge parses deadline and accepts matching query/fragment callbacks',
    () {
      final challenge = WechatChallenge.fromJson(valid, now: now);
      expect(challenge.expiresAt, now.add(const Duration(minutes: 10)));
      expect(
        challenge.ticketFromRedirect('${valid['serviceUrl']}&ticket=a%2Bb'),
        'a+b',
      );
      expect(
        challenge.ticketFromRedirect('${valid['serviceUrl']}#ticket=secret'),
        'secret',
      );
      expect(challenge.toString(), isNot(contains('state-1')));
    },
  );

  test('callback rejects wrong host, scheme, port, path, state and absent ticket', () {
    final challenge = WechatChallenge.fromJson(valid, now: now);
    for (final url in [
      'http://superapp.xjit.edu.cn/pages/tab/index/index?xjitApiState=state-1&ticket=x',
      'https://superapp.xjit.edu.cn.evil.example/pages/tab/index/index?xjitApiState=state-1&ticket=x',
      'https://superapp.xjit.edu.cn:444/pages/tab/index/index?xjitApiState=state-1&ticket=x',
      'https://superapp.xjit.edu.cn/other?xjitApiState=state-1&ticket=x',
      'https://superapp.xjit.edu.cn/pages/tab/index/index?xjitApiState=other&ticket=x',
      'https://superapp.xjit.edu.cn/pages/tab/index/index?ticket=x',
      '${valid['serviceUrl']}',
      '${valid['serviceUrl']}&ticket=',
    ]) {
      expect(challenge.ticketFromRedirect(url), isNull, reason: url);
    }
  });

  test('challenge rejects incomplete and unexpected authorization origins', () {
    for (final invalid in [
      <String, dynamic>{},
      {...valid, 'authUrl': 'http://cas.xjit.edu.cn/'},
      {...valid, 'authUrl': 'https://evil.example/'},
      {...valid, 'expiresInSeconds': -1},
    ]) {
      expect(
        () => WechatChallenge.fromJson(invalid, now: now),
        throwsA(isA<AuthFailure>()),
      );
    }
  });
}
