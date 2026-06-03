import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/xjit_api_client.dart';
import '../../api/xjit_features.dart';
import '../../auth/auth_controller.dart';
import '../common/async_content.dart';
import '../common/feature_data_page.dart';
import '../common/payment_webview_page.dart';

class ElectricityPage extends ConsumerStatefulWidget {
  const ElectricityPage({super.key});

  @override
  ConsumerState<ElectricityPage> createState() => _ElectricityPageState();
}

class _ElectricityPageState extends ConsumerState<ElectricityPage> {
  static const _roomKey = 'last_room_query';

  final _roomController = TextEditingController();
  Future<Map<String, dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    _restoreRoom();
  }

  @override
  void dispose() {
    _roomController.dispose();
    super.dispose();
  }

  Future<void> _restoreRoom() async {
    final storage = ref.read(secureStorageProvider);
    final room = await storage.read(key: _roomKey);
    if (!mounted || room == null || room.isEmpty) {
      return;
    }
    _roomController.text = room;
    final future = _load(room);
    setState(() {
      _future = future;
    });
  }

  AuthSession? _currentSession() {
    return ref
        .read(authControllerProvider)
        .when(
          data: (value) => value,
          error: (error, stackTrace) => null,
          loading: () => null,
        );
  }

  Future<Map<String, dynamic>> _load(String room) async {
    final session = _currentSession();
    if (session == null) {
      throw const XjitApiException('请先登录');
    }
    final cleanRoom = room.trim();
    if (cleanRoom.isEmpty) {
      throw const XjitApiException('请输入宿舍号，例如 9#312');
    }
    final storage = ref.read(secureStorageProvider);
    await storage.write(key: _roomKey, value: cleanRoom);

    return ref
        .read(xjitApiClientProvider)
        .run(
          XjitFeature.electricityAccount,
          username: session.username,
          password: session.password,
          params: {'roomQuery': cleanRoom},
        );
  }

  Future<void> _query() async {
    final future = _load(_roomController.text);
    setState(() {
      _future = future;
    });
    try {
      await future;
    } catch (_) {
      // FutureBuilder owns the visible error state.
    }
  }

  Future<void> _openRecharge() async {
    final session = _currentSession();
    if (session == null) {
      _showMessage('请先登录');
      return;
    }

    final room = _roomController.text.trim();
    if (room.isEmpty) {
      _showMessage('请先输入宿舍号');
      return;
    }

    final result = await showModalBottomSheet<_ElectricityRechargeResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      builder: (context) {
        return _ElectricityRechargeSheet(session: session, roomQuery: room);
      },
    );
    if (result == null || !mounted) {
      return;
    }

    if (result.payResult != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) {
            return PaymentWebViewPage(
              title: '电费缴费',
              payResult: result.payResult!,
            );
          },
        ),
      );
    }

    if (mounted) {
      await _query();
      if (mounted && result.message.isNotEmpty) {
        _showMessage(result.message);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('宿舍电费')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _roomController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _query(),
            decoration: const InputDecoration(
              labelText: '宿舍号',
              hintText: '例如 9#312',
              prefixIcon: Icon(Icons.meeting_room_outlined),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _query,
              icon: const Icon(Icons.bolt),
              label: const Text('查询剩余电量'),
            ),
          ),
          const SizedBox(height: 18),
          if (_future == null)
            const EmptyPanel(
              title: '输入宿舍号后查询',
              subtitle: '支持 9#312、5号楼524 这类写法。',
              icon: Icons.bolt_outlined,
            )
          else
            FutureBuilder<Map<String, dynamic>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingPanel();
                }
                if (snapshot.hasError) {
                  return ErrorPanel(error: snapshot.error!, onRetry: _query);
                }

                final data = snapshot.data ?? const <String, dynamic>{};
                final remaining = data['remainingElectricity'] is Map
                    ? Map<String, dynamic>.from(
                        data['remainingElectricity'] as Map,
                      )
                    : const <String, dynamic>{};
                final room = data['room'] is Map
                    ? Map<String, dynamic>.from(data['room'] as Map)
                    : const <String, dynamic>{};
                final value = textValue(remaining['value']);

                if (value == '-') {
                  return const EmptyPanel(title: '没有查到电费数据');
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('剩余电量'),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$value ${textValue(remaining['unit'], fallback: '度')}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .displaySmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _openRecharge,
                              icon: const Icon(Icons.payments_outlined),
                              label: const Text('缴电费'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InfoCard(
                      icon: Icons.apartment_outlined,
                      title: textValue(room['buildingName'], fallback: '宿舍'),
                      subtitle:
                          '${textValue(room['levelName'])} · ${textValue(room['roomName'])}',
                      trailing: Text(textValue(room['query'])),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ElectricityRechargeResult {
  const _ElectricityRechargeResult({this.payResult, required this.message});

  final Map<String, dynamic>? payResult;
  final String message;
}

class _ElectricityRechargeSheet extends ConsumerStatefulWidget {
  const _ElectricityRechargeSheet({
    required this.session,
    required this.roomQuery,
  });

  final AuthSession session;
  final String roomQuery;

  @override
  ConsumerState<_ElectricityRechargeSheet> createState() {
    return _ElectricityRechargeSheetState();
  }
}

class _ElectricityRechargeSheetState
    extends ConsumerState<_ElectricityRechargeSheet> {
  late Future<Map<String, dynamic>> _future;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String? _selectedPayCode;
  String? _errorText;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _future = _loadConfig();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadConfig() {
    return ref
        .read(xjitApiClientProvider)
        .run(
          XjitFeature.electricityRechargeConfig,
          username: widget.session.username,
          password: widget.session.password,
          params: {'roomQuery': widget.roomQuery},
        );
  }

  void _reloadConfig() {
    final future = _loadConfig();
    setState(() {
      _future = future;
    });
  }

  void _setAmount(String value) {
    setState(() {
      if (_amountController.text != value) {
        _amountController.text = value;
        _amountController.selection = TextSelection.collapsed(
          offset: value.length,
        );
      }
    });
  }

  Future<void> _pay(Map<String, dynamic> config) async {
    FocusManager.instance.primaryFocus?.unfocus();
    _clearError();

    final amount = _amountController.text.trim();
    final amountValue = double.tryParse(amount);
    if (amountValue == null || amountValue <= 0) {
      _showError('请输入有效缴费金额');
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

    final needPassword = config['needPaymentPassword'] == true;
    final password = _passwordController.text.trim();
    if (needPassword && password.isEmpty) {
      _showError('请输入一卡通支付密码');
      return;
    }

    final params = <String, dynamic>{
      'roomQuery': widget.roomQuery,
      'amount': amount,
      'payCode': payCode,
    };
    if (config['customfield'] is Map) {
      final customfield = Map<String, dynamic>.from(
        config['customfield'] as Map,
      );
      if (customfield.isNotEmpty) {
        params['customfield'] = customfield;
      }
    }
    final tradeType = textValue(payMethod['tradeType'], fallback: '');
    if (tradeType.isNotEmpty && tradeType != '-') {
      params['tradeType'] = tradeType;
    }
    if (password.isNotEmpty) {
      params['paymentPassword'] = password;
    }

    final confirmed = await _confirmPayment(config, payMethod, amount);
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _paying = true);
    var resetPaying = true;
    try {
      final data = await ref
          .read(xjitApiClientProvider)
          .run(
            XjitFeature.electricityRechargePay,
            username: widget.session.username,
            password: widget.session.password,
            params: params,
          );
      if (!mounted) {
        return;
      }

      final payResult = data['payResult'] is Map
          ? Map<String, dynamic>.from(data['payResult'] as Map)
          : const <String, dynamic>{};
      final webPayment = _hasWebPayment(payResult);
      resetPaying = false;
      Navigator.of(context).pop(
        _ElectricityRechargeResult(
          payResult: webPayment ? payResult : null,
          message: webPayment ? '已刷新电费信息' : '电费缴费成功',
        ),
      );
    } catch (error) {
      if (mounted) {
        _showError(error.toString());
      }
    } finally {
      if (mounted && resetPaying) {
        setState(() => _paying = false);
      }
    }
  }

  Future<bool?> _confirmPayment(
    Map<String, dynamic> config,
    Map<String, dynamic> payMethod,
    String amount,
  ) {
    final room = config['room'] is Map
        ? Map<String, dynamic>.from(config['room'] as Map)
        : const <String, dynamic>{};
    final roomName = [
      textValue(room['buildingName'], fallback: ''),
      textValue(room['roomName'], fallback: ''),
    ].where((item) => item.isNotEmpty).join(' ');
    final payName = textValue(payMethod['name'], fallback: '支付方式');

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('确认缴费'),
          content: Text(
            [
              if (roomName.isNotEmpty) roomName,
              '缴费金额：$amount 元',
              '支付方式：$payName',
            ].join('\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
  }

  bool _hasWebPayment(Map<String, dynamic> payResult) {
    return textValue(
          payResult['officialTransferUrl'],
          fallback: '',
        ).isNotEmpty ||
        textValue(payResult['h5Url'], fallback: '').isNotEmpty ||
        textValue(payResult['htmlPost'], fallback: '').isNotEmpty;
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _errorText = message);
  }

  void _clearError() {
    if (_errorText != null) {
      setState(() => _errorText = null);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                        '缴宿舍电费',
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
                      IconButton(
                        onPressed: _paying
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        tooltip: '取消',
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
                    _ElectricityRechargeForm(
                      config: snapshot.data ?? const <String, dynamic>{},
                      amountController: _amountController,
                      passwordController: _passwordController,
                      selectedPayCode: _selectedPayCode,
                      errorText: _errorText,
                      paying: _paying,
                      onAmountChanged: _setAmount,
                      onPayCodeChanged: (value) {
                        setState(() => _selectedPayCode = value);
                      },
                      onSubmit: () {
                        _pay(snapshot.data ?? const <String, dynamic>{});
                      },
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

class _ElectricityRechargeForm extends StatelessWidget {
  const _ElectricityRechargeForm({
    required this.config,
    required this.amountController,
    required this.passwordController,
    required this.selectedPayCode,
    required this.errorText,
    required this.paying,
    required this.onAmountChanged,
    required this.onPayCodeChanged,
    required this.onSubmit,
  });

  final Map<String, dynamic> config;
  final TextEditingController amountController;
  final TextEditingController passwordController;
  final String? selectedPayCode;
  final String? errorText;
  final bool paying;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onPayCodeChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final room = config['room'] is Map
        ? Map<String, dynamic>.from(config['room'] as Map)
        : const <String, dynamic>{};
    final remaining = config['remainingElectricity'] is Map
        ? Map<String, dynamic>.from(config['remainingElectricity'] as Map)
        : const <String, dynamic>{};
    final cardBalance = config['cardBalance'] is Map
        ? Map<String, dynamic>.from(config['cardBalance'] as Map)
        : const <String, dynamic>{};
    final price = config['price'] is Map
        ? Map<String, dynamic>.from(config['price'] as Map)
        : const <String, dynamic>{};
    final amountOptions = mapList(config['amountOptions']);
    final payMethods = mapList(config['payMethods']);
    final needPassword = config['needPaymentPassword'] == true;
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
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  textValue(room['buildingName'], fallback: '宿舍'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    textValue(room['levelName'], fallback: ''),
                    textValue(room['roomName'], fallback: ''),
                    textValue(room['query'], fallback: ''),
                  ].where((item) => item.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _MiniMetric(
                      label: '剩余',
                      value:
                          '${textValue(remaining['value'])}${textValue(remaining['unit'], fallback: '度')}',
                    ),
                    const SizedBox(width: 12),
                    _MiniMetric(
                      label: '卡余额',
                      value:
                          '${textValue(cardBalance['value'])}${textValue(cardBalance['unit'], fallback: '元')}',
                    ),
                    const SizedBox(width: 12),
                    _MiniMetric(
                      label: '单价',
                      value:
                          '${textValue(price['value'])}${textValue(price['unit'], fallback: '元/度')}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
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
              return ChoiceChip(
                label: Text(label),
                selected: amount == amountController.text.trim(),
                onSelected: (_) => onAmountChanged(amount),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '缴费金额', suffixText: '元'),
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
        if (needPassword) ...[
          const SizedBox(height: 12),
          TextField(
            controller: passwordController,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '一卡通支付密码',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
        ],
        const SizedBox(height: 18),
        if (errorText != null && errorText!.isNotEmpty) ...[
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 18,
                    color: colors.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errorText!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (paying) ...[
          LinearProgressIndicator(
            borderRadius: BorderRadius.circular(999),
            minHeight: 3,
          ),
          const SizedBox(height: 10),
          Text(
            '正在提交给学校支付系统',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: paying ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: paying ? null : onSubmit,
                  icon: paying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.payments_outlined),
                  label: Text(paying ? '正在缴费' : '确认缴费'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
