import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:xinli_lite/features/campus/campus.dart';
import 'package:xinli_lite/features/campus/data/campus_api.dart';

final Map<String, Map<String, dynamic>> examples = {
  for (final feature
      in (jsonDecode(
                File(
                  'test/features/campus/fixtures/features.json',
                ).readAsStringSync(),
              )
              as Map)['features']
          as List)
    feature['name'] as String: Map<String, dynamic>.from(
      feature['responseExample']['data'] as Map,
    ),
};
Map<String, dynamic> example(String feature) =>
    jsonDecode(jsonEncode(examples[feature])) as Map<String, dynamic>;

class StubAdapter implements HttpClientAdapter {
  StubAdapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return await respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody body(Object value, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(value),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

class FakeSession implements CampusSessionAccess {
  @override
  String? token = 'old-token';
  @override
  int revision = 1;
  int refreshes = 0, invalidations = 0;
  Future<void> Function()? onRefresh;
  @override
  Future<void> refresh({bool force = false}) async {
    if (!force) return;
    refreshes++;
    if (onRefresh != null) {
      await onRefresh!();
    } else {
      token = 'new-token';
    }
  }

  @override
  Future<void> invalidate(String rejectedToken) async {
    invalidations++;
    if (token == rejectedToken) {
      token = null;
      revision++;
    }
  }
}

class FakeCampusRepository implements CampusRepository {
  Future<StudentProfile> Function()? onProfile;
  Future<Schedule> Function(String? term)? onSchedule;
  Future<List<Exam>> Function()? onExams;
  Future<TransactionPage> Function(TransactionQuery query, int page)?
  onTransactions;
  Future<CampusCode> Function()? onCode;
  Future<PaymentOrder> Function()? onPay;
  Future<PaymentOrder> Function()? onOrder;
  int charges = 0, orders = 0, codeCalls = 0, profileCalls = 0;
  String? receivedPassword;
  @override
  Future<StudentProfile> profile() {
    profileCalls++;
    return onProfile?.call() ??
        Future.value(StudentProfile.fromJson(example('jw.profile')));
  }

  @override
  Future<Schedule> schedule({String? term}) =>
      onSchedule?.call(term) ??
      Future.value(Schedule.fromJson(example('jw.schedule')));
  @override
  Future<Grades> grades({
    String? term,
    GradeMode mode = GradeMode.bestByCourse,
  }) async => Grades.fromJson(example('jw.grades'));
  @override
  Future<List<Exam>> exams() =>
      onExams?.call() ??
      Future.value([const Exam(courseName: '课程', examTime: '待定')]);
  @override
  Future<List<TrainingRecord>> training() async => [];
  @override
  Future<List<CardAccount>> balance() async => [];
  @override
  Future<TransactionPage> transactions(
    TransactionQuery query, {
    int pageNo = 1,
  }) =>
      onTransactions?.call(query, pageNo) ??
      Future.value(TransactionPage.fromJson(example('newcard.transactions')));
  @override
  Future<CampusCode> campusCode({String qrcodeType = '', String? devCode}) {
    codeCalls++;
    return onCode?.call() ??
        Future.value(
          CampusCode.fromJson(
            example('newcard.campus_code.qrcode'),
            requestedAt: DateTime.now(),
          ),
        );
  }

  @override
  Future<CardRechargeConfig> cardRechargeConfig() async =>
      CardRechargeConfig.fromJson(example('newcard.recharge.config'));
  @override
  Future<PaymentOrder> createCardOrder({
    required MoneyAmount amount,
    required PayMethod method,
    String? otherStudentId,
    Uri? returnUrl,
    String? subOpenId,
    String? subAppId,
    Uri? signReturnUrl,
  }) {
    orders++;
    return onOrder?.call() ??
        Future.value(
          PaymentOrder.fromJson(example('newcard.recharge.create_order')),
        );
  }

  @override
  Future<ElectricityAccount> electricity(String roomQuery) async =>
      ElectricityAccount.fromJson(example('newcard.electricity.account'));
  @override
  Future<ElectricityRechargeConfig> electricityRechargeConfig(
    String roomQuery,
  ) async => ElectricityRechargeConfig.fromJson(
    example('newcard.electricity.recharge.config'),
  );
  @override
  Future<PaymentOrder> payElectricity({
    required String roomQuery,
    required MoneyAmount amount,
    required PayMethod method,
    String? paymentPassword,
    Uri? returnUrl,
    Map<String, dynamic> customFields = const {},
  }) {
    charges++;
    receivedPassword = paymentPassword;
    return onPay?.call() ??
        Future.value(
          PaymentOrder.fromJson(example('newcard.electricity.recharge.pay')),
        );
  }
}
