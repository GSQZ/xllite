import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/campus_failure.dart';
import '../domain/campus_repository.dart';
import '../domain/campus_local_data.dart';
import '../domain/card_models.dart';
import 'resource_controller.dart';

enum PaymentPhase {
  idle,
  submitting,
  awaitingExternalPayment,
  completed,
  failed,
  outcomeUnknown,
}

enum PaymentOperation { cardRecharge, electricity }

class PaymentState {
  const PaymentState({
    this.phase = PaymentPhase.idle,
    this.operation,
    this.order,
    this.failure,
    this.amount,
    this.room,
    this.otherStudentId,
  });
  final PaymentPhase phase;
  final PaymentOperation? operation;
  final PaymentOrder? order;
  final String? amount, room, otherStudentId;
  final CampusFailure? failure;
  bool get canSubmit =>
      phase == PaymentPhase.idle || phase == PaymentPhase.failed;
}

/// Only explicit submit calls create orders/charges. Never auto-replay mutations.
class PaymentController extends ChangeNotifier {
  PaymentController(this.repository);
  final CampusRepository repository;
  final cardConfig = ResourceController<CardRechargeConfig>(
    'newcard.recharge.config',
  );
  final electricityConfig = ResourceController<ElectricityRechargeConfig>(
    'newcard.electricity.recharge.config',
  );
  PaymentState _state = const PaymentState();
  PaymentState get state => _state;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _pending;
  Future<void>? _restored;

  Future<void> restorePending() => _restored ??= _restorePending();
  Future<void> _restorePending() async {
    final generation = _generation;
    final local = repository;
    if (local is! CampusLocalData) return;
    try {
      final value = await (local as CampusLocalData).readPreference(
        'pendingPayment',
      );
      if (_disposed || generation != _generation || value == null) return;
      final saved = jsonDecode(value) as Map<String, dynamic>;
      _state = PaymentState(
        amount: saved['amount'] as String?,
        room: saved['room'] as String?,
        otherStudentId: saved['otherStudentId'] as String?,
        phase: PaymentPhase.outcomeUnknown,
        operation: saved['operation'] == 'cardRecharge'
            ? PaymentOperation.cardRecharge
            : PaymentOperation.electricity,
        failure: const CampusFailure(
          CampusFailureKind.outcomeUnknown,
          '上次充值结果尚未核对，请先查看余额和交易记录',
        ),
      );
      notifyListeners();
    } catch (_) {
      if (!_disposed && generation == _generation) {
        _state = const PaymentState(
          phase: PaymentPhase.outcomeUnknown,
          failure: CampusFailure(
            CampusFailureKind.outcomeUnknown,
            '无法读取上次充值状态，请核对交易记录后继续',
          ),
        );
        notifyListeners();
      }
    }
  }

  Future<void> _journal(String? operation) async {
    final local = repository;
    if (local is CampusLocalData) {
      await (local as CampusLocalData).writePreference(
        'pendingPayment',
        operation,
      );
    }
  }

  Future<void> loadCardConfig({bool refresh = false}) async {
    await restorePending();
    await cardConfig.load(repository.cardRechargeConfig, refresh: refresh);
  }

  Future<void> loadElectricityConfig(
    String room, {
    bool refresh = false,
  }) async {
    await restorePending();
    await electricityConfig.load(
      () => repository.electricityRechargeConfig(room.trim()),
      key: room.trim(),
      refresh: refresh,
    );
  }

  PayMethod _method(List<PayMethod> methods, PayMethod selected) =>
      methods
          .where(
            (m) => m.code == selected.code && m.tradeType == selected.tradeType,
          )
          .firstOrNull ??
      (invalidInput('支付方式已变化，请刷新充值配置'));

  Future<void> submitCard({
    required String amount,
    required PayMethod method,
    String? otherStudentId,
    Uri? returnUrl,
    String? subOpenId,
    String? subAppId,
    Uri? signReturnUrl,
  }) => _submit(
    PaymentOperation.cardRecharge,
    () {
      final config = cardConfig.state.data;
      if (config == null || cardConfig.state.phase != ResourcePhase.ready) {
        invalidInput('请先加载充值配置');
      }
      if (otherStudentId != null &&
          otherStudentId.trim().isNotEmpty &&
          !config.canPayOther) {
        invalidInput('当前不支持为他人充值');
      }
      return repository.createCardOrder(
        amount: MoneyAmount.parse(amount),
        method: _method(config.payMethods, method),
        otherStudentId: otherStudentId,
        returnUrl: returnUrl,
        subOpenId: subOpenId,
        subAppId: subAppId,
        signReturnUrl: signReturnUrl,
      );
    },
    amount: amount,
    otherStudentId: otherStudentId?.trim(),
  );

  Future<void> submitElectricity({
    required String room,
    required String amount,
    required PayMethod method,
    String? paymentPassword,
    Uri? returnUrl,
    Map<String, dynamic> customFields = const {},
  }) => _submit(
    PaymentOperation.electricity,
    () {
      final config = electricityConfig.state.data;
      if (config == null ||
          electricityConfig.state.phase != ResourcePhase.ready ||
          electricityConfig.state.key != room.trim()) {
        invalidInput('请先加载该宿舍的充值配置');
      }
      final selected = _method(config.payMethods, method);
      final money = MoneyAmount.parse(amount);
      if (selected.code == '06' &&
          config.needPaymentPassword &&
          (paymentPassword == null || paymentPassword.isEmpty)) {
        invalidInput('请输入一卡通支付密码');
      }
      if (config.amtInputDisabled &&
          !config.amountOptions.any(
            (o) => MoneyAmount.parse(o.amount).value == money.value,
          )) {
        invalidInput('请选择学校提供的充值金额');
      }
      return repository.payElectricity(
        roomQuery: room.trim(),
        amount: money,
        method: selected,
        paymentPassword: paymentPassword,
        returnUrl: returnUrl,
        customFields: {...config.customFields, ...customFields},
      );
    },
    amount: amount,
    room: room.trim(),
  );

  Future<void> _submit(
    PaymentOperation operation,
    Future<PaymentOrder> Function() send, {
    required String amount,
    String? room,
    String? otherStudentId,
  }) {
    if (_disposed) return Future.value();
    if (_pending != null) return _pending!;
    if (!state.canSubmit) return Future.value();
    final generation = ++_generation;
    _state = PaymentState(phase: PaymentPhase.submitting, operation: operation);
    final future = Future<void>(() async {
      if (_disposed || generation != _generation) return;
      try {
        try {
          await _journal(
            jsonEncode({
              'operation': operation.name,
              'amount': amount,
              'room': ?room,
              'otherStudentId': ?otherStudentId,
            }),
          );
        } catch (_) {
          throw const CampusFailure(
            CampusFailureKind.rejected,
            '无法保存充值状态，未提交付款，请稍后重试',
          );
        }
        if (_disposed || generation != _generation) return;
        final result = await send();
        if (_disposed || generation != _generation) return;
        // Creating a card order is not proof of payment. Only the documented
        // electricity balance_payment response confirms an immediate debit.
        _state = PaymentState(
          phase:
              operation == PaymentOperation.electricity &&
                  result.result.type == PaymentResultType.balancePayment
              ? PaymentPhase.completed
              : PaymentPhase.awaitingExternalPayment,
          operation: operation,
          amount: amount,
          room: room,
          otherStudentId: otherStudentId,
          order: result,
        );
        if (_state.phase == PaymentPhase.completed) {
          try {
            await _journal(null);
          } catch (_) {
            /* Keep conservative restart guard. */
          }
        }
      } catch (error) {
        if (_disposed || generation != _generation) return;
        final failure = campusFailure(
          error,
          operation == PaymentOperation.cardRecharge
              ? 'newcard.recharge.create_order'
              : 'newcard.electricity.recharge.pay',
        );
        _state = PaymentState(
          phase: failure.kind == CampusFailureKind.outcomeUnknown
              ? PaymentPhase.outcomeUnknown
              : PaymentPhase.failed,
          operation: operation,
          amount: amount,
          room: room,
          otherStudentId: otherStudentId,
          failure: failure,
        );
        if (_state.phase == PaymentPhase.failed) {
          try {
            await _journal(null);
          } catch (_) {
            /* Keep conservative restart guard. */
          }
        }
      }
      if (!_disposed && generation == _generation) {
        _pending = null;
        notifyListeners();
      }
    });
    _pending = future;
    notifyListeners();
    return future;
  }

  /// UI may call only after explicit user intent to start a separate payment.
  /// Unknown/pending results require the user to check balance/transactions first.
  void beginNewPayment({bool previousOutcomeChecked = false}) {
    if (_disposed || state.phase == PaymentPhase.submitting) return;
    if ((state.phase == PaymentPhase.outcomeUnknown ||
            state.phase == PaymentPhase.awaitingExternalPayment) &&
        !previousOutcomeChecked) {
      return;
    }
    _state = const PaymentState();
    _journal(null).catchError((Object _) {});
    cardConfig.reset();
    electricityConfig.reset();
    notifyListeners();
  }

  /// Session boundary only. Page disposal must not discard a pending payment.
  void resetSession() {
    if (_disposed) return;
    _generation++;
    _restored = null;
    _pending = null;
    _state = const PaymentState();
    cardConfig.reset();
    electricityConfig.reset();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    cardConfig.dispose();
    electricityConfig.dispose();
    super.dispose();
  }
}
