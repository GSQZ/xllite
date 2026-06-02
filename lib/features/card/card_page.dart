import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final session = ref.read(authControllerProvider).when(
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
    await _future;
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
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
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
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
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
        title: textValue(item['merchantName'], fallback: textValue(item['summary'])),
        subtitle:
            '${textValue(item['date'])}\n${textValue(item['summary'])} · 流水 ${textValue(item['journo'])}',
        trailing: Text(
          textValue(item['amount']),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}
