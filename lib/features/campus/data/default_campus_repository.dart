import 'dart:async';
import 'dart:convert';

import '../domain/academic_models.dart';
import '../domain/campus_local_data.dart';
import '../domain/campus_failure.dart';
import '../domain/campus_repository.dart';
import '../domain/card_models.dart';
import '../domain/json_fields.dart';
import '../domain/records.dart';
import 'campus_api.dart';
import 'campus_store.dart';

class DefaultCampusRepository implements CampusRepository, CampusLocalData {
  DefaultCampusRepository(
    this.api, {
    DateTime Function()? now,
    this.store,
    this.account,
  }) : _now = now ?? DateTime.now;
  final CampusApi api;
  final DateTime Function() _now;
  final CampusStore? store;
  final String? Function()? account;
  final _pendingReads = <String, Future<Json>>{};
  int _cacheGeneration = 0;
  String? get _scope {
    final user = account?.call();
    return user == null || user.isEmpty
        ? null
        : '${api.dio.options.baseUrl}|$user';
  }

  static const _cacheable = {
    'jw.profile',
    'jw.schedule',
    'jw.grades',
    'jw.exams',
    'jw.training',
    'newcard.balance',
    'newcard.electricity.account',
    'newcard.transactions',
  };
  String _cacheKey(String op, Json params) => '$op:${jsonEncode(params)}';

  @override
  Future<CachedData<T>?> readCached<T>(String operation, {Object? key}) async {
    final scope = _scope;
    if (store == null || scope == null || !_cacheable.contains(operation)) {
      return null;
    }
    final params = switch (operation) {
      'jw.schedule' => _term(key as String?),
      'jw.grades' => {
        ..._term((key as (String?, GradeMode)).$1),
        'mode': key.$2.wireName,
      },
      'newcard.electricity.account' => {'roomQuery': key as String},
      'newcard.transactions' => (key as TransactionQuery).params(1),
      _ => <String, dynamic>{},
    };
    final snapshot = await store!.read(
      scope,
      _cacheKey(operation, params),
      operation.startsWith('newcard.')
          ? const Duration(days: 1)
          : const Duration(days: 30),
    );
    if (snapshot == null || scope != _scope) return null;
    try {
      final j = snapshot.data;
      final Object result = switch (operation) {
        'jw.profile' => StudentProfile.fromJson(j),
        'jw.schedule' => Schedule.fromJson(j),
        'jw.grades' => Grades.fromJson(j),
        'jw.exams' => listValue(j['exams'], Exam.fromJson),
        'jw.training' => listValue(j['training'], TrainingRecord.fromJson),
        'newcard.balance' => listValue(j['accounts'], CardAccount.fromJson),
        'newcard.electricity.account' => ElectricityAccount.fromJson(j),
        'newcard.transactions' => TransactionPage.fromJson(j),
        _ => throw const FormatException(),
      };
      return CachedData(result as T, snapshot.updatedAt);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> readPreference(String key) async {
    final scope = _scope;
    if (scope == null || store == null) return null;
    final value = await store!.preference(scope, key);
    return scope == _scope ? value : null;
  }

  @override
  Future<void> writePreference(String key, String? value) async {
    final scope = _scope;
    if (scope != null && store != null) {
      await store!.setPreference(scope, key, value);
    }
  }

  @override
  Future<void> clearCache() async {
    _cacheGeneration++;
    final scope = _scope;
    if (scope != null && store != null) await store!.clear(scope);
  }

  Future<T> _run<T>(
    CampusFeature feature,
    T Function(Json) parse, [
    Json params = const {},
  ]) async {
    try {
      final scope = _scope;
      final revision = api.session.revision;
      final cacheGeneration = _cacheGeneration;
      final key = _cacheKey(feature.wireName, params);
      final requestKey = '$revision:$scope:$key';
      final Future<Json> request;
      if (_cacheable.contains(feature.wireName)) {
        request = _pendingReads.putIfAbsent(
          requestKey,
          () => api.run(feature, params),
        );
      } else {
        request = api.run(feature, params);
      }
      final Json json;
      try {
        json = await request;
      } finally {
        if (identical(_pendingReads[requestKey], request)) {
          _pendingReads.remove(requestKey);
        }
      }
      try {
        final result = parse(json);
        if (store != null &&
            scope != null &&
            scope == _scope &&
            revision == api.session.revision &&
            cacheGeneration == _cacheGeneration &&
            (feature != CampusFeature.transactions || params['pageNo'] == 1) &&
            _cacheable.contains(feature.wireName)) {
          unawaited(store!.put(scope, key, json).catchError((Object _) {}));
        }
        return result;
      } catch (_) {
        if (feature.mutation) {
          throw const CampusFailure(
            CampusFailureKind.outcomeUnknown,
            '交易响应无法识别，请先核对余额和流水',
          );
        }
        rethrow;
      }
    } catch (error) {
      throw campusFailure(error, feature.wireName);
    }
  }

  Json _term(String? term) {
    if (term == null || term.trim().isEmpty) return {};
    return {'term': term.trim()};
  }

  String _room(String room) {
    if (room.trim().isEmpty) invalidInput('请输入宿舍号');
    return room.trim();
  }

  String _url(Uri value) {
    if (value.scheme != 'https' ||
        value.host.isEmpty ||
        value.userInfo.isNotEmpty) {
      invalidInput('回跳地址必须为 HTTPS 地址');
    }
    return value.toString();
  }

  Json _payment(MoneyAmount amount, PayMethod method, Uri? returnUrl) {
    if (method.code.trim().isEmpty) invalidInput('请选择支付方式');
    return {
      'amount': amount.value,
      'payCode': method.code,
      if (method.tradeType != null) 'tradeType': method.tradeType,
      if (returnUrl != null) 'returnUrl': _url(returnUrl),
    };
  }

  @override
  Future<StudentProfile> profile() =>
      _run(CampusFeature.profile, StudentProfile.fromJson);
  @override
  Future<Schedule> schedule({String? term}) =>
      _run(CampusFeature.schedule, Schedule.fromJson, _term(term));
  @override
  Future<Grades> grades({
    String? term,
    GradeMode mode = GradeMode.bestByCourse,
  }) => _run(CampusFeature.grades, Grades.fromJson, {
    ..._term(term),
    'mode': mode.wireName,
  });
  @override
  Future<List<Exam>> exams() =>
      _run(CampusFeature.exams, (j) => listValue(j['exams'], Exam.fromJson));
  @override
  Future<List<TrainingRecord>> training() => _run(
    CampusFeature.training,
    (j) => listValue(j['training'], TrainingRecord.fromJson),
  );
  @override
  Future<List<CardAccount>> balance() => _run(
    CampusFeature.balance,
    (j) => listValue(j['accounts'], CardAccount.fromJson),
  );
  @override
  Future<TransactionPage> transactions(
    TransactionQuery query, {
    int pageNo = 1,
  }) => _run(
    CampusFeature.transactions,
    TransactionPage.fromJson,
    query.params(pageNo),
  );
  @override
  Future<CampusCode> campusCode({String qrcodeType = '', String? devCode}) {
    // Start the validity window before network latency, never extend a credential.
    final requestedAt = _now();
    return _run(
      CampusFeature.campusCode,
      (j) => CampusCode.fromJson(j, requestedAt: requestedAt),
      {'qrcodeType': qrcodeType, 'devCode': ?devCode},
    );
  }

  @override
  Future<CardRechargeConfig> cardRechargeConfig() =>
      _run(CampusFeature.cardConfig, CardRechargeConfig.fromJson);
  @override
  Future<PaymentOrder> createCardOrder({
    required MoneyAmount amount,
    required PayMethod method,
    String? otherStudentId,
    Uri? returnUrl,
    String? subOpenId,
    String? subAppId,
    Uri? signReturnUrl,
  }) => _run(CampusFeature.cardOrder, PaymentOrder.fromJson, {
    ..._payment(amount, method, returnUrl),
    if (otherStudentId != null && otherStudentId.trim().isNotEmpty)
      'otherIdserial': otherStudentId.trim(),
    'subOpenId': ?subOpenId,
    'subAppId': ?subAppId,
    if (signReturnUrl != null) 'signReturnUrl': _url(signReturnUrl),
  });
  @override
  Future<ElectricityAccount> electricity(String roomQuery) => _run(
    CampusFeature.electricity,
    ElectricityAccount.fromJson,
    {'roomQuery': _room(roomQuery)},
  );
  @override
  Future<ElectricityRechargeConfig> electricityRechargeConfig(
    String roomQuery,
  ) => _run(
    CampusFeature.electricityConfig,
    ElectricityRechargeConfig.fromJson,
    {'roomQuery': _room(roomQuery)},
  );
  @override
  Future<PaymentOrder> payElectricity({
    required String roomQuery,
    required MoneyAmount amount,
    required PayMethod method,
    String? paymentPassword,
    Uri? returnUrl,
    Map<String, dynamic> customFields = const {},
  }) => _run(CampusFeature.electricityPay, PaymentOrder.fromJson, {
    ..._payment(amount, method, returnUrl),
    'roomQuery': _room(roomQuery),
    'paymentPassword': ?paymentPassword,
    'customfield': customFields,
  });
}
