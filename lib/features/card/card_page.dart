import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/xjit_api_client.dart';
import '../../api/xjit_features.dart';
import '../../auth/auth_controller.dart';
import '../common/async_content.dart';
import '../common/feature_data_page.dart';

class CardPage extends ConsumerStatefulWidget {
  const CardPage({super.key});

  @override
  ConsumerState<CardPage> createState() => _CardPageState();
}

class _CardPageState extends ConsumerState<CardPage> {
  late Future<CardSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<CardSnapshot> _load() async {
    final session = ref
        .read(authControllerProvider)
        .when(
          data: (value) => value,
          error: (error, stackTrace) => null,
          loading: () => null,
        );
    if (session == null) {
      throw const XjitApiException('请先登录');
    }
    final api = ref.read(xjitApiClientProvider);
    final results = await Future.wait([
      api.run(
        XjitFeature.cardBalance,
        username: session.username,
        password: session.password,
      ),
      api.run(
        XjitFeature.cardTransactions,
        username: session.username,
        password: session.password,
        params: const {'pageSize': 20},
      ),
    ]);
    return CardSnapshot(balance: results[0], transactions: results[1]);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    try {
      await _future;
    } catch (_) {
      // FutureBuilder owns the visible error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('校园卡'),
        actions: [
          IconButton(
            onPressed: _openPaymentCode,
            icon: const Icon(Icons.qr_code_2_outlined),
            tooltip: '付款码',
          ),
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ],
      ),
      body: FutureBuilder<CardSnapshot>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel();
          }
          if (snapshot.hasError) {
            return ErrorPanel(error: snapshot.error!, onRetry: _refresh);
          }

          final data = snapshot.data!;
          final accounts = mapList(data.balance['accounts']);
          final transactions = mapList(data.transactions['transactions']);

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '账户余额',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (accounts.isEmpty)
                  const EmptyPanel(title: '没有校园卡余额数据')
                else
                  ...accounts.map(_BalanceCard.new),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '最近流水',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      '${textValue(data.transactions['fromDate'])} - ${textValue(data.transactions['toDate'])}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (transactions.isEmpty)
                  const EmptyPanel(title: '最近没有校园卡流水')
                else
                  ...transactions.map(_TransactionCard.new),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openPaymentCode() async {
    final session = ref
        .read(authControllerProvider)
        .when(
          data: (value) => value,
          error: (error, stackTrace) => null,
          loading: () => null,
        );
    if (session == null || !mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PaymentCodeSheet(session: session),
    );
  }
}

class CardSnapshot {
  const CardSnapshot({required this.balance, required this.transactions});

  final Map<String, dynamic> balance;
  final Map<String, dynamic> transactions;
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard(this.item);

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InfoCard(
        icon: Icons.account_balance_wallet_outlined,
        title: textValue(item['typeName'], fallback: '账户'),
        subtitle: '账户类型 ${textValue(item['typeCode'])}',
        trailing: Text(
          '${textValue(item['balance'])} ${textValue(item['unit'], fallback: '元')}',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard(this.item);

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InfoCard(
        icon: Icons.receipt_long_outlined,
        title: textValue(
          item['merchantName'],
          fallback: textValue(item['summary']),
        ),
        subtitle:
            '${textValue(item['date'])}\n${textValue(item['summary'])} · 流水 ${textValue(item['journo'])}',
        trailing: Text(
          textValue(item['amount']),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _PaymentCodeSheet extends ConsumerStatefulWidget {
  const _PaymentCodeSheet({required this.session});

  final AuthSession session;

  @override
  ConsumerState<_PaymentCodeSheet> createState() => _PaymentCodeSheetState();
}

class _PaymentCodeSheetState extends ConsumerState<_PaymentCodeSheet> {
  Future<Map<String, dynamic>>? _future;
  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    _refreshCode();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refreshCode() {
    _timer?.cancel();
    setState(() {
      _secondsLeft = 0;
      _future = _requestCode();
    });
  }

  Future<Map<String, dynamic>> _requestCode() async {
    final data = await ref
        .read(xjitApiClientProvider)
        .run(
          XjitFeature.campusPaymentCode,
          username: widget.session.username,
          password: widget.session.password,
        );
    if (mounted) {
      _startCountdown(data);
    }
    return data;
  }

  void _startCountdown(Map<String, dynamic> data) {
    final expires =
        int.tryParse(textValue(data['expiresInSeconds'], fallback: '30')) ?? 30;
    _timer?.cancel();
    setState(() => _secondsLeft = expires);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        _refreshCode();
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      '校园付款码',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _refreshCode,
                      icon: const Icon(Icons.refresh),
                      tooltip: '刷新',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 54),
                    child: CircularProgressIndicator(),
                  )
                else if (snapshot.hasError)
                  ErrorPanel(error: snapshot.error!, onRetry: _refreshCode)
                else
                  _PaymentCodeContent(
                    data: snapshot.data ?? const <String, dynamic>{},
                    secondsLeft: _secondsLeft,
                  ),
                const SizedBox(height: 12),
                Text(
                  '仅限本人付款使用',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PaymentCodeContent extends StatelessWidget {
  const _PaymentCodeContent({required this.data, required this.secondsLeft});

  final Map<String, dynamic> data;
  final int secondsLeft;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final code = textValue(data['qrcode'], fallback: '');
    final balance = textValue(data['balance'], fallback: '');
    final userName = textValue(data['userName'], fallback: '');
    final displayBalance = data['displayBalance'] == true && balance.isNotEmpty;
    final displayInfo = data['displayInfo'] == true && userName.isNotEmpty;

    if (code.isEmpty) {
      return const EmptyPanel(
        title: '付款码为空',
        subtitle: '请刷新后再试。',
        icon: Icons.qr_code_2_outlined,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: QrImageView(
              data: code,
              version: QrVersions.auto,
              size: 230,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (displayInfo) ...[
                  Expanded(
                    child: Text(
                      userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (displayBalance) ...[
                  Text(
                    '余额 $balance',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          secondsLeft > 0 ? '$secondsLeft 秒后刷新' : '正在刷新',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
