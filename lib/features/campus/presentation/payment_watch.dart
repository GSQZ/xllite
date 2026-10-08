import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xinli_lite/features/campus/campus.dart';

/// A spend inferred from the balance while the payment code was shown.
class DetectedPayment {
  const DetectedPayment({
    required this.amount,
    required this.balance,
    this.merchant = '',
  });

  /// Positive amount that left the main account, in yuan.
  final double amount;
  final double balance;
  final String merchant;

  DetectedPayment withMerchant(String merchant) =>
      DetectedPayment(amount: amount, balance: balance, merchant: merchant);
}

/// Infers "paid" from the campus card balance, because the school system
/// has no payment-result API for the scan code.
///
/// The first balance read after [start] is the baseline. While running it
/// re-reads the balance every [interval] (slower after [slowAfter], stopped
/// after [giveUpAfter]). A drop of at least one cent is reported once as a
/// [DetectedPayment]; a rise (refund, top-up) just moves the baseline.
/// It then refreshes the transaction list and, if the newest matching
/// amount is found, adds its merchant. This is a heuristic: a payment made
/// elsewhere at the same moment would also be reported.
class PaymentWatch extends ChangeNotifier {
  PaymentWatch(
    this.campus, {
    this.interval = const Duration(seconds: 3),
    this.slowInterval = const Duration(seconds: 6),
    this.slowAfter = const Duration(minutes: 2),
    this.giveUpAfter = const Duration(minutes: 10),
  });

  final CampusController campus;
  final Duration interval, slowInterval, slowAfter, giveUpAfter;

  DetectedPayment? _payment;
  DetectedPayment? get payment => _payment;

  double? _baseline;
  DateTime? _startedAt;
  Timer? _timer;
  var _running = false;
  var _paused = false;
  var _busy = false;
  var _disposed = false;

  void start() {
    if (_running || _payment != null || _disposed) return;
    _running = true;
    _startedAt = DateTime.now();
    _tick();
  }

  /// App went to the background / came back.
  void setPaused(bool paused) {
    if (_paused == paused) return;
    _paused = paused;
    _timer?.cancel();
    if (!paused && _running) _tick();
  }

  void _schedule() {
    _timer?.cancel();
    if (!_running || _paused || _disposed) return;
    final elapsed = DateTime.now().difference(_startedAt!);
    if (elapsed > giveUpAfter) {
      _running = false;
      return;
    }
    _timer = Timer(elapsed > slowAfter ? slowInterval : interval, _tick);
  }

  Future<void> _tick() async {
    if (!_running || _paused || _busy || _disposed) return;
    _busy = true;
    await campus.loadBalance(refresh: true);
    _busy = false;
    if (_disposed || !_running) return;
    final state = campus.balance.state;
    final main = state.failure == null ? state.data?.firstOrNull : null;
    final value = main == null ? null : double.tryParse(main.balance.trim());
    if (value != null) {
      final base = _baseline;
      if (base == null || value > base) {
        _baseline = value;
      } else if (base - value >= 0.005) {
        _found(DetectedPayment(amount: base - value, balance: value));
        return;
      }
    }
    _schedule();
  }

  void _found(DetectedPayment payment) {
    _running = false;
    _timer?.cancel();
    _payment = payment;
    notifyListeners();
    unawaited(_lookUpMerchant(payment));
  }

  Future<void> _lookUpMerchant(DetectedPayment payment) async {
    await campus.transactions.load();
    if (_disposed || !identical(_payment, payment)) return;
    for (final t in campus.transactions.state.items.take(5)) {
      final amount = double.tryParse(
        t.amount.replaceAll(RegExp(r'[^0-9.\-]'), ''),
      );
      if (amount == null || (amount.abs() - payment.amount).abs() > 0.005) {
        continue;
      }
      final name = t.merchantName.isNotEmpty ? t.merchantName : t.summary;
      if (name.isEmpty) return;
      _payment = payment.withMerchant(name);
      notifyListeners();
      return;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
