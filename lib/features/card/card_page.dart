import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../api/xjit_api_client.dart';
import '../../api/xjit_features.dart';
import '../../auth/auth_controller.dart';
import '../common/async_content.dart';
import '../common/feature_data_page.dart';
import '../common/payment_webview_page.dart';

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
    final future = _load();
    setState(() {
      _future = future;
    });
    try {
      await future;
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '账户余额',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    _CardHeaderAction(
                      icon: Icons.qr_code_2_outlined,
                      tooltip: '付款码',
                      onTap: _openPaymentCode,
                    ),
                    const SizedBox(width: 8),
                    _CardHeaderAction(
                      icon: Icons.add_card_outlined,
                      tooltip: '充值',
                      onTap: _openRecharge,
                    ),
                  ],
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

  Future<void> _openRecharge() async {
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

    final order = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _RechargeSheet(session: session),
    );
    if (order == null || !mounted) {
      return;
    }
    final payResult = order['payResult'] is Map
        ? Map<String, dynamic>.from(order['payResult'] as Map)
        : const <String, dynamic>{};

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PaymentWebViewPage(title: '一卡通充值', payResult: payResult),
      ),
    );
    if (mounted) {
      await _refresh();
    }
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

class _CardHeaderAction extends StatelessWidget {
  const _CardHeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 19, color: colors.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
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

class _RechargeSheet extends ConsumerStatefulWidget {
  const _RechargeSheet({required this.session});

  final AuthSession session;

  @override
  ConsumerState<_RechargeSheet> createState() => _RechargeSheetState();
}

class _RechargeSheetState extends ConsumerState<_RechargeSheet> {
  late Future<Map<String, dynamic>> _future;
  final TextEditingController _amountController = TextEditingController();
  String? _selectedPayCode;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _future = _loadConfig();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadConfig() {
    return ref
        .read(xjitApiClientProvider)
        .run(
          XjitFeature.rechargeConfig,
          username: widget.session.username,
          password: widget.session.password,
        );
  }

  void _reloadConfig() {
    final future = _loadConfig();
    setState(() {
      _future = future;
    });
  }

  Future<void> _createOrder(Map<String, dynamic> config) async {
    final amount = _amountController.text.trim();
    final amountValue = double.tryParse(amount);
    if (amountValue == null || amountValue <= 0) {
      _showError('请输入有效充值金额');
      return;
    }

    final payMethods = mapList(config['payMethods']);
    if (payMethods.isEmpty) {
      _showError('没有可用支付方式');
      return;
    }
    final payMethod = payMethods.firstWhere(
      (item) => textValue(item['code'], fallback: '') == _selectedPayCode,
      orElse: () => payMethods.first,
    );
    final payCode = textValue(payMethod['code'], fallback: '');
    if (payCode.isEmpty) {
      _showError('支付方式缺少编码');
      return;
    }

    setState(() => _creating = true);
    try {
      final order = await ref
          .read(xjitApiClientProvider)
          .run(
            XjitFeature.rechargeCreateOrder,
            username: widget.session.username,
            password: widget.session.password,
            params: {
              'amount': amount,
              'payCode': payCode,
              'tradeType': textValue(payMethod['tradeType'], fallback: 'WAP'),
            },
          );
      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(order);
    } catch (error) {
      if (mounted) {
        _showError(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            14,
            18,
            18 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _future,
            builder: (context, snapshot) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '一卡通充值',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _reloadConfig,
                        icon: const Icon(Icons.refresh),
                        tooltip: '刷新',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 54),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (snapshot.hasError)
                    ErrorPanel(error: snapshot.error!, onRetry: _reloadConfig)
                  else
                    _RechargeForm(
                      config: snapshot.data ?? const <String, dynamic>{},
                      amountController: _amountController,
                      selectedPayCode: _selectedPayCode,
                      creating: _creating,
                      onAmountChanged: (value) {
                        setState(() => _amountController.text = value);
                      },
                      onPayCodeChanged: (value) {
                        setState(() => _selectedPayCode = value);
                      },
                      onSubmit: () {
                        _createOrder(
                          snapshot.data ?? const <String, dynamic>{},
                        );
                      },
                    ),
                  const SizedBox(height: 10),
                  Text(
                    '下单后会打开学校支付页面，支付完成后返回并刷新余额。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RechargeForm extends StatelessWidget {
  const _RechargeForm({
    required this.config,
    required this.amountController,
    required this.selectedPayCode,
    required this.creating,
    required this.onAmountChanged,
    required this.onPayCodeChanged,
    required this.onSubmit,
  });

  final Map<String, dynamic> config;
  final TextEditingController amountController;
  final String? selectedPayCode;
  final bool creating;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onPayCodeChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final amountOptions = mapList(config['amountOptions']);
    final payMethods = mapList(config['payMethods']);
    final balance = textValue(config['balance'], fallback: '');
    final userName = textValue(config['username'], fallback: '');
    final activePayCode =
        selectedPayCode ??
        (payMethods.isEmpty
            ? ''
            : textValue(payMethods.first['code'], fallback: ''));

    if (amountController.text.trim().isEmpty && amountOptions.isNotEmpty) {
      amountController.text = textValue(
        amountOptions.first['amount'],
        fallback: '',
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (balance.isNotEmpty || userName.isNotEmpty) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      userName.isEmpty ? '本人一卡通' : userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (balance.isNotEmpty)
                    Text(
                      '余额 $balance',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text(
          '金额',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (amountOptions.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: amountOptions.map((option) {
              final amount = textValue(option['amount'], fallback: '');
              final label = textValue(option['name'], fallback: '$amount 元');
              final selected = amount == amountController.text.trim();
              return ChoiceChip(
                label: Text(label),
                selected: selected,
                onSelected: (_) => onAmountChanged(amount),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '充值金额', suffixText: '元'),
          onChanged: onAmountChanged,
        ),
        const SizedBox(height: 14),
        Text(
          '支付方式',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (payMethods.isEmpty)
          const EmptyPanel(title: '没有可用支付方式')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: payMethods.map((method) {
              final code = textValue(method['code'], fallback: '');
              return ChoiceChip(
                label: Text(textValue(method['name'], fallback: '支付方式')),
                selected: code == activePayCode,
                onSelected: (_) => onPayCodeChanged(code),
              );
            }).toList(),
          ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: creating ? null : onSubmit,
          icon: creating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.payment_outlined),
          label: Text(creating ? '正在下单' : '去支付'),
        ),
      ],
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
