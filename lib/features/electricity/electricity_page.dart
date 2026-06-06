import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/xjit_api_client.dart';
import '../../api/xjit_features.dart';
import '../../auth/auth_controller.dart';
import '../../ui/xl_theme.dart';
import '../../ui/xl_widgets.dart';
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

  Future<Map<String, dynamic>> _load(
    String room, {
    bool forceRefresh = false,
  }) async {
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
        .read(xjitApiCacheProvider)
        .run(
          XjitFeature.electricityAccount,
          username: session.username,
          accessToken: session.accessToken,
          params: {'roomQuery': cleanRoom},
          forceRefresh: forceRefresh,
        );
  }

  Future<void> _query() async {
    final future = _load(_roomController.text, forceRefresh: true);
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
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          XLCard(
            radius: 20,
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '宿舍号',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: XLColors.inkSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _roomController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _query(),
                        decoration: const InputDecoration(
                          hintText: '例如 5#524',
                          prefixIcon: Icon(LucideIcons.building2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: FilledButton(
                        onPressed: _query,
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                        child: const Icon(LucideIcons.search, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '输入楼号和宿舍号，查询后可直接缴电费。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: XLColors.inkTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_future == null)
            const EmptyPanel(
              title: '输入宿舍号后查询',
              subtitle: '查询后会显示剩余电量和宿舍信息。',
              icon: LucideIcons.zap,
            )
          else
            FutureBuilder<Map<String, dynamic>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingPanel();
                }
                if (snapshot.hasError) {
                  return ErrorPanel(
                    error: snapshot.error!,
                    onRetry: () => _query(),
                  );
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
                    _ElectricityBalanceCard(
                      remaining: remaining,
                      onRecharge: _openRecharge,
                    ),
                    const SizedBox(height: 10),
                    InfoCard(
                      icon: LucideIcons.building2,
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

class _ElectricityBalanceCard extends StatelessWidget {
  const _ElectricityBalanceCard({
    required this.remaining,
    required this.onRecharge,
  });

  final Map<String, dynamic> remaining;
  final VoidCallback onRecharge;

  @override
  Widget build(BuildContext context) {
    final value = textValue(remaining['value']);
    final unit = textValue(remaining['unit'], fallback: '度');
    final number = double.tryParse(value);
    final lowPower = number != null && number < 10;
    final statusText = lowPower ? '电量偏低' : '状态正常';
    final statusColor = lowPower ? XLColors.warning : XLColors.success;

    return XLCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const XLIconBox(
                icon: LucideIcons.zap,
                color: XLColors.brandSoft,
                iconColor: XLColors.brand,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '剩余电量',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: XLColors.ink,
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text.rich(
                    TextSpan(
                      text: value,
                      children: [
                        TextSpan(
                          text: unit,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    style: const TextStyle(
                      color: XLColors.ink,
                      fontSize: 58,
                      fontWeight: FontWeight.w900,
                      height: 0.95,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: onRecharge,
                icon: const Icon(LucideIcons.walletCards, size: 18),
                label: const Text('去缴费'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '数据来自学校一卡通系统，下拉或点击查询可刷新。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: XLColors.inkSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
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
          accessToken: widget.session.accessToken,
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
            accessToken: widget.session.accessToken,
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
            10,
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
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: XLColors.line,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        '缴宿舍电费',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      XLIconButton(
                        onTap: _reloadConfig,
                        icon: LucideIcons.refreshCw,
                        tooltip: '刷新',
                        size: 38,
                      ),
                      const SizedBox(width: 8),
                      XLIconButton(
                        onTap: _paying
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: LucideIcons.x,
                        tooltip: '取消',
                        size: 38,
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
        XLCard(
          radius: 18,
          color: XLColors.surfaceMuted,
          borderColor: Colors.transparent,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const XLIconBox(
                    icon: LucideIcons.building2,
                    size: 38,
                    iconSize: 20,
                    color: XLColors.surface,
                    iconColor: XLColors.brand,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      textValue(room['buildingName'], fallback: '宿舍'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: XLColors.ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                [
                  textValue(room['levelName'], fallback: ''),
                  textValue(room['roomName'], fallback: ''),
                  textValue(room['query'], fallback: ''),
                ].where((item) => item.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: XLColors.inkSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
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
        const SizedBox(height: 14),
        Text(
          '金额',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: XLColors.inkSecondary,
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
              return _ChoicePill(
                label: Text(label),
                selected: amount == amountController.text.trim(),
                onTap: () => onAmountChanged(amount),
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
            color: XLColors.inkSecondary,
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
              return _ChoicePill(
                label: Text(textValue(method['name'], fallback: '支付方式')),
                selected: code == activePayCode,
                onTap: () => onPayCodeChanged(code),
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
              prefixIcon: Icon(LucideIcons.lockKeyhole),
            ),
          ),
        ],
        const SizedBox(height: 18),
        if (errorText != null && errorText!.isNotEmpty) ...[
          _SheetErrorBanner(message: errorText!),
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
              color: XLColors.inkSecondary,
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
                      : const Icon(LucideIcons.walletCards, size: 18),
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
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: XLColors.inkSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: XLColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Widget label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? XLColors.brandSoft : XLColors.surface,
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? XLColors.brand.withValues(alpha: 0.18)
                  : XLColors.line,
              width: 1.1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(LucideIcons.check, size: 16, color: XLColors.brand),
                const SizedBox(width: 7),
              ],
              DefaultTextStyle.merge(
                style: TextStyle(
                  color: selected ? XLColors.ink : XLColors.inkSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
                child: label,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetErrorBanner extends StatelessWidget {
  const _SheetErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: XLColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: XLColors.danger.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              LucideIcons.circleAlert,
              size: 18,
              color: XLColors.danger,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: XLColors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
