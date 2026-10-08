import 'campus_failure.dart';
import 'json_fields.dart';
import 'records.dart';
import 'school_notice.dart';

class Quantity {
  const Quantity(this.value, this.unit);
  final String value, unit;
  double? get numericValue => optionalNumber(value);
  factory Quantity.fromJson(Json json) => Quantity(
    textValue(json['value'], required: true),
    textValue(json['unit'], required: true),
  );
}

class PayMethod {
  const PayMethod({
    required this.code,
    required this.name,
    this.tradeType,
    this.h5 = false,
    this.successToHome = false,
    this.signBind,
  });
  final String code, name;
  final String? tradeType;
  final bool h5, successToHome;
  final Object? signBind;
  factory PayMethod.fromJson(Json json) => PayMethod(
    code: textValue(json['code'], required: true),
    name: textValue(json['name']),
    tradeType: json['tradeType'] == null ? null : textValue(json['tradeType']),
    h5: boolValue(json['h5']),
    successToHome: boolValue(json['successToHome']),
    signBind: json['signBind'],
  );
}

/// Exact decimal validation for outgoing amounts, with no floating point rounding.
class MoneyAmount {
  MoneyAmount._(this.value);
  final String value;
  factory MoneyAmount.parse(String input) {
    final value = input.trim();
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value) ||
        !RegExp('[1-9]').hasMatch(value)) {
      invalidInput('请输入大于 0 的金额，最多两位小数');
    }
    final parts = value.split('.');
    final whole = BigInt.parse(parts[0]).toString();
    return MoneyAmount._(
      '$whole.${parts.length == 1 ? '00' : parts[1].padRight(2, '0')}',
    );
  }
  @override
  String toString() => value;
}

class CardRechargeConfig {
  CardRechargeConfig.fromJson(Json json)
    : balance = textValue(json['balance'], required: true),
      studentId = textValue(json['idSerial']),
      name = textValue(json['username']),
      amountOptions = listValue(json['amountOptions'], AmountOption.fromJson),
      payMethods = listValue(json['payMethods'], PayMethod.fromJson),
      canPayOther = boolValue(json['canPayOther']),
      hostApp = boolValue(json['hostApp']),
      daLianPayEnable = boolValue(json['daLianPayEnable']),
      wapPayEnable = boolValue(json['wapPayEnable']);
  final String balance, studentId, name;
  final List<AmountOption> amountOptions;
  final List<PayMethod> payMethods;
  final bool canPayOther, hostApp, daLianPayEnable, wapPayEnable;
}

class ElectricityAccount {
  ElectricityAccount.fromJson(Json json)
    : room = DormRoom.fromJson(objectValue(json['room'])),
      remainingElectricity = Quantity.fromJson(
        objectValue(json['remainingElectricity']),
      );
  final DormRoom room;
  final Quantity remainingElectricity;
}

class ElectricityRechargeConfig {
  ElectricityRechargeConfig.fromJson(Json json)
    : room = DormRoom.fromJson(objectValue(json['room'])),
      account = UtilityAccount.fromJson(objectValue(json['account'])),
      remainingElectricity = Quantity.fromJson(
        objectValue(json['remainingElectricity']),
      ),
      cardBalance = Quantity.fromJson(objectValue(json['cardBalance'])),
      price = Quantity.fromJson(objectValue(json['price'])),
      amountOptions = listValue(json['amountOptions'], AmountOption.fromJson),
      payMethods = listValue(json['payMethods'], PayMethod.fromJson),
      needPaymentPassword = boolValue(
        json['needPaymentPassword'],
        fallback: true,
      ),
      canPayOther = boolValue(json['canPayOther']),
      confirm = boolValue(json['confirm']),
      hostApp = boolValue(json['hostApp']),
      daLianPayEnable = boolValue(json['daLianPayEnable']),
      amtInputDisabled = boolValue(json['amtInputDisabled']),
      customFields = json['customfield'] == null
          ? const {}
          : Map.unmodifiable(objectValue(json['customfield'])),
      tip = schoolNoticeText(textValue(json['tip']));
  final DormRoom room;
  final UtilityAccount account;
  final Quantity remainingElectricity, cardBalance, price;
  final List<AmountOption> amountOptions;
  final List<PayMethod> payMethods;
  final bool needPaymentPassword,
      canPayOther,
      confirm,
      hostApp,
      daLianPayEnable,
      amtInputDisabled;
  final String tip;
  final Json customFields;
}

class TransactionQuery {
  const TransactionQuery({
    this.fromDate,
    this.toDate,
    this.tradeType = '1,2,3',
    this.pageSize = 20,
  });
  final DateTime? fromDate, toDate;
  final String tradeType;
  final int pageSize;
  Json params(int pageNo) {
    if (pageSize < 1 || pageSize > 100 || pageNo < 1) invalidInput('流水分页参数无效');
    if (fromDate != null &&
        toDate != null &&
        _date(fromDate!).compareTo(_date(toDate!)) > 0) {
      invalidInput('开始日期不能晚于结束日期');
    }
    if (!RegExp(r'^[123](,[123])*$').hasMatch(tradeType)) {
      invalidInput('交易类型无效');
    }
    return {
      'pageNo': pageNo,
      'pageSize': pageSize,
      'tradeType': tradeType,
      if (fromDate != null) 'fromDate': _date(fromDate!),
      if (toDate != null) 'toDate': _date(toDate!),
    };
  }

  String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class TransactionPage {
  TransactionPage.fromJson(Json json)
    : fromDate = textValue(json['fromDate']),
      toDate = textValue(json['toDate']),
      tradeType = textValue(json['tradeType']),
      pageNo = integerValue(json['pageNo']),
      pageSize = integerValue(json['pageSize']),
      transactions = listValue(json['transactions'], CardTransaction.fromJson) {
    if (pageNo < 1 || pageSize < 1 || pageSize > 100) invalidData();
  }
  final String fromDate, toDate, tradeType;
  final int pageNo, pageSize;
  final List<CardTransaction> transactions;
  // The API has no total/hasMore field. A full final page needs one extra query.
  bool get mayHaveMore => transactions.length >= pageSize;
}

class CampusCode {
  CampusCode.fromJson(Json json, {required DateTime requestedAt})
    : value = textValue(json['qrcode'], required: true),
      mode = textValue(json['mode']),
      qrcodeType = textValue(json['qrcodeType']),
      balance = textValue(json['balance']),
      studentId = textValue(json['idSerial']),
      name = textValue(json['userName']),
      displayInfo = boolValue(json['displayInfo']),
      displayBalance = boolValue(json['displayBalance']),
      expiresAt = requestedAt.add(
        Duration(seconds: integerValue(json['expiresInSeconds'])),
      ) {
    if (!expiresAt.isAfter(requestedAt)) invalidData();
  }
  final String value, mode, qrcodeType, balance, studentId, name;
  final bool displayInfo, displayBalance;
  final DateTime expiresAt;
  bool isExpired(DateTime now) => !now.isBefore(expiresAt);
  @override
  String toString() => 'CampusCode([redacted])';
}

enum PaymentResultType {
  balancePayment,
  htmlPost,
  h5,
  wechatJsapi,
  unsupported,
}

class PaymentResult {
  PaymentResult.fromJson(Json json)
    : wireType = textValue(json['type'], required: true),
      payCode = textValue(json['payCode']),
      partnerJourno = textValue(json['partnerJourno']),
      htmlPost = textValue(json['htmlPost']),
      h5Url = _url(json['h5Url']),
      officialTransferUrl = _url(json['officialTransferUrl']),
      wechatJsapi = json['wechatJsapi'] == null
          ? null
          : Map.unmodifiable(objectValue(json['wechatJsapi']));
  final String wireType, payCode, partnerJourno, htmlPost;
  final Uri? h5Url, officialTransferUrl;
  final Json? wechatJsapi;
  PaymentResultType get type => switch (wireType) {
    'balance_payment' => PaymentResultType.balancePayment,
    'html_post' => PaymentResultType.htmlPost,
    'h5' || 'h5_url' => PaymentResultType.h5,
    'wechat_jsapi' => PaymentResultType.wechatJsapi,
    _ => PaymentResultType.unsupported,
  };
  Uri? get preferredUrl => officialTransferUrl ?? h5Url;
  Map<String, String> get h5Headers =>
      payCode == '02' && officialTransferUrl == null
      ? const {'Referer': 'https://newcard.xjit.edu.cn/'}
      : const {};
  static Uri? _url(Object? value) {
    if (value == null || value == '') return null;
    final uri = Uri.tryParse(textValue(value));
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      invalidData();
    }
    return uri;
  }

  @override
  String toString() => 'PaymentResult(type: $wireType, payload: [redacted])';
}

class PaymentOrder {
  PaymentOrder.fromJson(Json json)
    : amount = textValue(json['amount'], required: true),
      payMethod = PayMethod.fromJson(objectValue(json['payMethod'])),
      partnerJourno = textValue(json['partnerJourno']),
      result = PaymentResult.fromJson(objectValue(json['payResult'])),
      room = json['room'] == null
          ? null
          : DormRoom.fromJson(objectValue(json['room'])),
      account = json['account'] == null
          ? null
          : UtilityAccount.fromJson(objectValue(json['account']));
  final String amount, partnerJourno;
  final PayMethod payMethod;
  final PaymentResult result;
  final DormRoom? room;
  final UtilityAccount? account;
  @override
  String toString() => 'PaymentOrder([redacted])';
}
