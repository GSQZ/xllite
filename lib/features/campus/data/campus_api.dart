import 'package:dio/dio.dart';

import '../../auth/auth.dart';
import '../domain/campus_failure.dart';
import '../domain/json_fields.dart';

abstract interface class CampusSessionAccess {
  int get revision;
  String? get token;
  Future<void> refresh({bool force = false});
  Future<void> invalidate(String rejectedToken);
}

class AuthCampusSession implements CampusSessionAccess {
  AuthCampusSession(this.auth);
  final AuthController auth;
  @override
  int get revision => auth.sessionRevision;
  @override
  String? get token =>
      auth.state.isAuthenticated ? auth.state.session?.accessToken : null;
  @override
  Future<void> refresh({bool force = false}) async {
    final previousFailure = auth.state.failure;
    await auth.refreshSession(force: force);
    final failure = auth.state.failure;
    if (failure != null &&
        !identical(failure, previousFailure) &&
        failure.operation == AuthOperation.refresh) {
      throw CampusFailure(switch (failure.kind) {
        AuthFailureKind.network => CampusFailureKind.network,
        AuthFailureKind.unauthorized ||
        AuthFailureKind.expired => CampusFailureKind.unauthenticated,
        _ => CampusFailureKind.server,
      }, failure.message);
    }
  }

  @override
  Future<void> invalidate(String rejectedToken) =>
      auth.invalidateSession(rejectedToken);
}

/// The two payment commands are deliberately excluded from automatic replay.
enum CampusFeature {
  profile('jw.profile'),
  schedule('jw.schedule'),
  grades('jw.grades'),
  exams('jw.exams'),
  training('jw.training'),
  balance('newcard.balance'),
  transactions('newcard.transactions'),
  campusCode('newcard.campus_code.qrcode'),
  cardConfig('newcard.recharge.config'),
  cardOrder('newcard.recharge.create_order', mutation: true),
  electricity('newcard.electricity.account'),
  electricityConfig('newcard.electricity.recharge.config'),
  electricityPay('newcard.electricity.recharge.pay', mutation: true);

  const CampusFeature(this.wireName, {this.mutation = false});
  final String wireName;
  final bool mutation;
}

class CampusApi {
  CampusApi(this.dio, this.session);
  final Dio dio;
  final CampusSessionAccess session;

  Future<Json> run(CampusFeature feature, [Json params = const {}]) async {
    final revision = session.revision;
    void checkSession() {
      if (revision != session.revision) {
        throw const CampusFailure(CampusFailureKind.cancelled, '登录状态已改变');
      }
      if (session.token == null) {
        throw const CampusFailure(CampusFailureKind.unauthenticated, '请重新登录');
      }
    }

    try {
      checkSession();
      await session.refresh();
      checkSession();
      for (var attempt = 0; attempt < 2; attempt++) {
        final token = session.token!;
        final Response<Object?> response;
        try {
          response = await dio.post<Object?>(
            '/api/v1/run',
            data: {'feature': feature.wireName, 'params': params},
            options: Options(
              headers: {'Authorization': 'Bearer $token'},
              followRedirects: false,
              validateStatus: (_) => true,
            ),
          );
        } on DioException {
          checkSession();
          throw CampusFailure(
            feature.mutation
                ? CampusFailureKind.outcomeUnknown
                : CampusFailureKind.network,
            feature.mutation ? '未能确认交易结果，请先核对余额和流水，勿重复支付' : '网络连接失败，请检查网络后重试',
          );
        }
        checkSession();
        final status = response.statusCode ?? 0;
        if (status == 401) {
          if (attempt == 0) {
            // Another parallel request may already have rotated this token.
            if (session.token == token) await session.refresh(force: true);
            checkSession();
            if (!feature.mutation && session.token != token) continue;
          }
          if (session.token == token) await session.invalidate(token);
          throw const CampusFailure(
            CampusFailureKind.unauthenticated,
            '登录校验未通过，请重新登录或重试',
          );
        }
        if (status == 403) {
          throw const CampusFailure(CampusFailureKind.forbidden, '当前账号无权使用此功能');
        }
        if (status >= 500 || status == 0) {
          throw CampusFailure(
            feature.mutation
                ? CampusFailureKind.outcomeUnknown
                : CampusFailureKind.server,
            feature.mutation ? '服务未能确认交易结果，请先核对余额和流水' : '学校服务暂时不可用，请稍后重试',
          );
        }
        if (status == 429) {
          throw const CampusFailure(CampusFailureKind.server, '请求过于频繁，请稍后重试');
        }
        if (status < 200 || status >= 300) {
          throw const CampusFailure(
            CampusFailureKind.rejected,
            '请求未完成，请检查输入或稍后重试',
          );
        }
        try {
          final body = objectValue(response.data);
          if (body['ok'] is! bool) invalidData();
          if (body['ok'] == false) {
            throw const CampusFailure(
              CampusFailureKind.rejected,
              '学校系统未通过此请求，请检查输入或稍后重试',
            );
          }
          return objectValue(body['data']);
        } on CampusFailure catch (e) {
          if (feature.mutation && e.kind == CampusFailureKind.invalidResponse) {
            throw const CampusFailure(
              CampusFailureKind.outcomeUnknown,
              '交易响应不完整，请先核对余额和流水',
            );
          }
          rethrow;
        }
      }
      throw const CampusFailure(CampusFailureKind.unauthenticated, '请重新登录');
    } catch (error) {
      throw campusFailure(error, feature.wireName);
    }
  }
}
