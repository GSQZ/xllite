enum AuthFailureKind {
  validation,
  rejected,
  unauthorized,
  network,
  server,
  invalidResponse,
  storage,
  expired,
}

enum AuthOperation { restore, signIn, refresh, signOut, wechat }

/// Safe, user-facing failure. Never retains credentials or a raw HTTP response.
class AuthFailure implements Exception {
  const AuthFailure(this.kind, this.message, {this.operation});

  final AuthFailureKind kind;
  final String message;
  final AuthOperation? operation;

  @override
  String toString() => message;
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.username,
    required this.source,
    required this.expiresAt,
  });

  final String accessToken;
  final String username;
  final String source;
  final DateTime? expiresAt;

  bool isExpired(DateTime now) =>
      expiresAt != null && !now.isBefore(expiresAt!);

  bool needsRefresh(DateTime now) =>
      expiresAt == null ||
      !now.add(const Duration(minutes: 2)).isBefore(expiresAt!);

  factory AuthSession.fromJson(
    Map<String, dynamic> json, {
    required DateTime now,
    AuthSession? fallback,
    String? fallbackUsername,
    String fallbackSource = 'password',
  }) {
    final token = _text(json['accessToken']);
    final tokenType = _text(json['tokenType']);
    if (token.isEmpty || (tokenType.isNotEmpty && tokenType != 'Bearer')) {
      throw const AuthFailure(AuthFailureKind.invalidResponse, '登录信息不完整，请重试');
    }
    DateTime? expiresAt;
    final absolute = _integer(json['expiresAt']);
    final relative = _integer(json['expiresInSeconds']);
    if ((json['expiresAt'] != null && absolute == null) ||
        (absolute == null &&
            json['expiresInSeconds'] != null &&
            relative == null)) {
      throw const AuthFailure(AuthFailureKind.invalidResponse, '登录有效期格式错误，请重试');
    }
    try {
      if (absolute != null) {
        expiresAt = DateTime.fromMillisecondsSinceEpoch(
          absolute > 100000000000 ? absolute : absolute * 1000,
          isUtc: true,
        );
      } else if (relative != null) {
        expiresAt = now.toUtc().add(Duration(seconds: relative));
      }
    } on ArgumentError {
      throw const AuthFailure(AuthFailureKind.invalidResponse, '登录有效期格式错误，请重试');
    }
    return AuthSession(
      accessToken: token,
      username: _text(json['username']).isNotEmpty
          ? _text(json['username'])
          : fallback?.username ?? fallbackUsername ?? '',
      source: _text(json['source']).isNotEmpty
          ? _text(json['source'])
          : fallback?.source ?? fallbackSource,
      expiresAt: expiresAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'tokenType': 'Bearer',
    'username': username,
    'source': source,
    if (expiresAt != null)
      'expiresAt': expiresAt!.millisecondsSinceEpoch ~/ 1000,
  };

  @override
  String toString() => 'AuthSession(source: $source, token: [redacted])';
}

class WechatChallenge {
  const WechatChallenge({
    required this.state,
    required this.authUrl,
    required this.serviceUrl,
    required this.expiresAt,
  });

  final String state;
  final Uri authUrl;
  final Uri serviceUrl;
  final DateTime expiresAt;

  factory WechatChallenge.fromJson(
    Map<String, dynamic> json, {
    required DateTime now,
  }) {
    final state = _text(json['state']);
    final auth = Uri.tryParse(_text(json['authUrl']));
    final service = Uri.tryParse(_text(json['serviceUrl']));
    final lifetime = _integer(json['expiresInSeconds']);
    if (state.isEmpty ||
        auth == null ||
        auth.scheme != 'https' ||
        auth.host != 'cas.xjit.edu.cn' ||
        service == null ||
        service.scheme != 'https' ||
        service.host != 'superapp.xjit.edu.cn' ||
        lifetime == null ||
        lifetime <= 0 ||
        lifetime > 86400) {
      throw const AuthFailure(
        AuthFailureKind.invalidResponse,
        '扫码登录入口无效，请重新获取',
      );
    }
    return WechatChallenge(
      state: state,
      authUrl: auth,
      serviceUrl: service,
      expiresAt: now.add(Duration(seconds: lifetime)),
    );
  }

  /// Only the registered service and this challenge's state may complete login.
  /// Returns null for ordinary WebView navigation; never logs the ticket URL.
  String? ticketFromRedirect(String redirectUrl) {
    final uri = Uri.tryParse(redirectUrl);
    if (uri == null ||
        uri.scheme != serviceUrl.scheme ||
        uri.host != serviceUrl.host ||
        uri.port != serviceUrl.port ||
        uri.path != serviceUrl.path ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    try {
      final parameters = <String, String>{...uri.queryParameters};
      if (uri.fragment.isNotEmpty) {
        final fragment = uri.fragment;
        parameters.addAll(
          Uri.splitQueryString(
            fragment.contains('?')
                ? fragment.substring(fragment.indexOf('?') + 1)
                : fragment,
          ),
        );
      }
      if (parameters['xjitApiState'] != state) return null;
      final ticket = parameters['ticket'];
      return ticket == null || ticket.trim().isEmpty ? null : ticket;
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => 'WechatChallenge([redacted])';
}

enum WechatStatus { pending, success, expired, error }

class WechatResult {
  const WechatResult(this.status, {this.session});

  final WechatStatus status;
  final AuthSession? session;
}

enum AuthPhase {
  idle,
  restoring,
  signedOut,
  signingIn,
  wechatStarting,
  wechatPending,
  wechatCompleting,
  authenticated,
  signingOut,
}

class AuthState {
  const AuthState({
    this.phase = AuthPhase.idle,
    this.session,
    this.challenge,
    this.failure,
    this.isRefreshing = false,
  });

  final AuthPhase phase;
  final AuthSession? session;
  final WechatChallenge? challenge;
  final AuthFailure? failure;
  final bool isRefreshing;

  bool get isAuthenticated => phase == AuthPhase.authenticated;
  bool get isBusy =>
      isRefreshing ||
      const {
        AuthPhase.restoring,
        AuthPhase.signingIn,
        AuthPhase.wechatStarting,
        AuthPhase.wechatCompleting,
        AuthPhase.signingOut,
      }.contains(phase);
}

String _text(Object? value) => value is String ? value.trim() : '';

int? _integer(Object? value) =>
    value is int ? value : int.tryParse(value?.toString() ?? '');
