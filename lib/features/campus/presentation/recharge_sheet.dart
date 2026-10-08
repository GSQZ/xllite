import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/drawn_keypad.dart';
import '../../../shared/widgets/frosted.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/status_banner.dart';
import '../../../shared/widgets/top_sheet.dart';
import 'feature_page.dart';
import 'pay_brand_icon.dart';
import 'payment_success.dart';
import 'payment_watch.dart';
import 'payment_webview_page.dart';
import 'section_parts.dart';

/// Opens campus-card (or, with [room], dorm electricity) top-up as a sheet
/// that drops from the top, like the payment code.
Future<void> showRechargeSheet(
  BuildContext context, {
  required CampusController campus,
  String? room,
  Widget Function(PaymentResult)? paymentBuilder,
}) => showTopSheet<void>(
  context,
  builder: (_) =>
      RechargeFlow(campus: campus, room: room, paymentBuilder: paymentBuilder),
);

enum _Step { form, confirm, done, pending }

/// Which drawn keypad is open (only one at a time).
enum _Pad { none, amount, other, password }

/// Top-up inside a sheet: fill in → confirm → success / 等待到账.
///
/// Business rules kept from the payment controller:
/// - nothing is charged without the confirm step;
/// - a request in flight blocks re-submits and closing;
/// - the password is sent once and cleared on submit and in the background;
/// - only the electricity `balance_payment` response is shown as success;
///   returning from the school checkout is never treated as paid;
/// - a pending order (also after a restart) must be acknowledged before a
///   new top-up can start.
///
/// For your own campus card the sheet watches the balance after checkout;
/// a rise of at least the amount is shown as "充值已到账".
class RechargeFlow extends StatefulWidget {
  const RechargeFlow({
    super.key,
    required this.campus,
    this.room,
    this.paymentBuilder,
    this.onBack,
  });

  final CampusController campus;
  final String? room;

  /// Replaces the checkout WebView (tests).
  final Widget Function(PaymentResult)? paymentBuilder;

  /// Shown as a back arrow when the flow is embedded in another sheet.
  final VoidCallback? onBack;

  @override
  State<RechargeFlow> createState() => _RechargeFlowState();
}

class _RechargeFlowState extends State<RechargeFlow>
    with WidgetsBindingObserver {
  final _amount = TextEditingController();
  final _password = TextEditingController();
  final _otherId = TextEditingController();
  PayMethod? _selected;
  bool _other = false;
  String? _error;
  var _step = _Step.form;
  var _direction = 1;

  // Snapshot shown on the confirm step and used for the charge.
  String _amountValue = '';
  _Form? _confirmForm;

  // Outcome.
  String _doneTitle = '', _donePrefix = '¥';

  // Balance watch after checkout (own campus card only).
  Timer? _watch;
  double? _baseline;
  Set<String> _knownJournos = const {};
  DateTime? _watchStarted;
  var _pad = _Pad.none;

  /// True from leaving checkout until arrival is seen or the watch gives up.
  var _watching = false;
  bool _watchBusy = false;

  PaymentController get payments => widget.campus.payments;
  bool get electric => widget.room != null;

  late final _listen = Listenable.merge([
    payments,
    payments.cardConfig,
    payments.electricityConfig,
    widget.campus.balance,
    widget.campus.electricity,
  ]);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (payments.state.phase == PaymentPhase.completed) {
        payments.beginNewPayment();
      }
      _load();
    });
  }

  Future<void> _load() => electric
      ? payments.loadElectricityConfig(widget.room!, refresh: true)
      : Future.wait([
          payments.loadCardConfig(refresh: true),
          widget.campus.loadBalance(refresh: true),
          widget.campus.transactions.load(),
        ]);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watch?.cancel();
    _amount.dispose();
    _password.dispose();
    _otherId.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _password.clear();
      return;
    }
    if (payments.state.phase == PaymentPhase.awaitingExternalPayment) {
      _refresh();
    } else if (payments.state.canSubmit && _step == _Step.form) {
      _load();
    }
  }

  void _go(_Step step, {int direction = 1}) {
    if (!mounted) return;
    setState(() {
      _direction = direction;
      _step = step;
    });
  }

  void _close() => Navigator.of(context).maybePop();

  /// Quietly refreshes what the user would check.
  Future<void> _refresh() async {
    final campus = widget.campus;
    final room = payments.state.room ?? widget.room;
    await Future.wait([
      campus.loadBalance(refresh: true),
      campus.transactions.load(),
      if (room != null && campus.roomQuery == room)
        campus.loadElectricity(room, refresh: true),
    ]);
  }

  Future<void> _openPayment() async {
    final result = payments.state.order?.result;
    if (result == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            widget.paymentBuilder?.call(result) ??
            PaymentWebViewPage(result: result),
      ),
    );
    if (!mounted) return;
    unawaited(_refresh());
    _startWatch();
  }

  /// Own-card top-up: watch for the money to arrive.
  ///
  /// Two independent signals, both read from the same sources as the
  /// "before" snapshot: the main account balance rising by the amount, or a
  /// new transaction (unseen before paying) for the same amount. Polls every
  /// 3 s for two minutes, then every 8 s, giving up after ten minutes.
  void _startWatch() {
    final state = payments.state;
    if (electric ||
        (state.otherStudentId?.isNotEmpty ?? false) ||
        state.phase != PaymentPhase.awaitingExternalPayment) {
      return;
    }
    _watchStarted ??= DateTime.now();
    _watching = true;
    _scheduleWatch(Duration.zero);
  }

  void _scheduleWatch(Duration delay) {
    _watch?.cancel();
    _watch = Timer(delay, _tickWatch);
  }

  /// Main account balance as a number, from the balance query.
  double? _mainBalance() {
    final main = widget.campus.balance.state.data?.firstOrNull;
    return main == null ? null : double.tryParse(main.balance.trim());
  }

  Future<void> _tickWatch() async {
    if (_watchBusy || !mounted || _step != _Step.pending) return;
    final elapsed = DateTime.now().difference(_watchStarted!);
    if (elapsed > const Duration(minutes: 10)) {
      _watch?.cancel();
      setState(() => _watching = false);
      return;
    }
    _watchBusy = true;
    await Future.wait([
      widget.campus.loadBalance(refresh: true),
      widget.campus.transactions.load(),
    ]);
    _watchBusy = false;
    if (!mounted || _step != _Step.pending) return;
    if (_arrived()) {
      _watch?.cancel();
      payments.beginNewPayment(previousOutcomeChecked: true);
      setState(() {
        _watching = false;
        _doneTitle = '充值已到账';
        _donePrefix = '+¥';
        _direction = 1;
        _step = _Step.done;
      });
      return;
    }
    _scheduleWatch(
      elapsed < const Duration(minutes: 2)
          ? const Duration(seconds: 3)
          : const Duration(seconds: 8),
    );
  }

  bool _arrived() {
    final paid = double.tryParse(_amountValue);
    if (paid == null) return false;
    final now = _mainBalance();
    if (now != null && _baseline != null && now >= _baseline! + paid - 0.005) {
      return true;
    }
    for (final t in widget.campus.transactions.state.items.take(10)) {
      if (t.journo.isEmpty || _knownJournos.contains(t.journo)) continue;
      final amount = double.tryParse(
        t.amount.replaceAll(RegExp(r'[^0-9.\-]'), ''),
      );
      if (amount != null && (amount.abs() - paid).abs() < 0.005) return true;
    }
    return false;
  }

  /// The user says the money is there: release the lock and finish.
  void _confirmArrived() {
    _watch?.cancel();
    payments.beginNewPayment(previousOutcomeChecked: true);
    setState(() {
      _watching = false;
      _doneTitle = '充值完成';
      _donePrefix = '+¥';
      _direction = 1;
      _step = _Step.done;
    });
  }

  void _togglePad(_Pad pad) {
    HapticFeedback.selectionClick();
    setState(() => _pad = _pad == pad ? _Pad.none : pad);
  }

  TextEditingController _controllerFor(_Pad pad) => switch (pad) {
    _Pad.amount => _amount,
    _Pad.other => _otherId,
    _ => _password,
  };

  /// Applies an edit; null means the key was rejected.
  void _edit(_Pad pad, String? next) {
    if (next == null) {
      HapticFeedback.mediumImpact();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _controllerFor(pad).text = next;
      _error = null;
      // Sixth digit entered: the PIN is complete, put the keypad away.
      if (pad == _Pad.password && next.length == 6) _pad = _Pad.none;
    });
  }

  /// The drawn keypad under [pad]'s field, expanded while it is active.
  Widget _keypadFor(_Pad pad, bool busy) {
    final open = _pad == pad && !busy;
    final controller = _controllerFor(pad);
    return AnimatedSize(
      duration: AppMotion.medium,
      curve: AppMotion.emphasized,
      alignment: Alignment.topCenter,
      child: open
          ? Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm + 2),
              child: DrawnKeypad(
                special: pad == _Pad.amount ? '.' : null,
                specialLabel: '小数点',
                keyPrefix: '${pad.name}.key.',
                onKey: (k) => _edit(
                  pad,
                  pad == _Pad.amount
                      ? appendAmount(controller.text, k)
                      : appendDigit(
                          controller.text,
                          k,
                          max: pad == _Pad.other ? 16 : 6,
                        ),
                ),
                onDelete: () => _edit(
                  pad,
                  controller.text.isEmpty
                      ? ''
                      : controller.text.substring(
                          0,
                          controller.text.length - 1,
                        ),
                ),
                onClear: () => _edit(pad, ''),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }

  void _newPayment() {
    payments.beginNewPayment(previousOutcomeChecked: true);
    setState(() {
      _selected = null;
      _error = null;
    });
    _load();
  }

  void _next(_Form form) {
    if (form.method == null) return;
    _pad = _Pad.none;
    try {
      _amountValue = MoneyAmount.parse(_amount.text).value;
      if (_other && _otherId.text.trim().isEmpty) {
        throw const CampusFailure(CampusFailureKind.validation, '请输入对方学号');
      }
      if (form.needPassword && _password.text.isEmpty) {
        throw const CampusFailure(CampusFailureKind.validation, '请输入一卡通支付密码');
      }
      if (form.needPassword && _password.text.length != 6) {
        throw const CampusFailure(CampusFailureKind.validation, '请输入 6 位支付密码');
      }
    } on CampusFailure catch (e) {
      HapticFeedback.mediumImpact();
      setState(() => _error = e.message);
      return;
    }
    _confirmForm = form;
    _error = null;
    _go(_Step.confirm);
  }

  Future<void> _confirm() async {
    final form = _confirmForm;
    final method = form?.method;
    if (form == null || method == null || !payments.state.canSubmit) return;
    final password = _password.text;
    _password.clear();
    // "Before" figures from the same queries the arrival watch polls.
    _baseline = _mainBalance();
    _knownJournos = {
      for (final t in widget.campus.transactions.state.items)
        if (t.journo.isNotEmpty) t.journo,
    };
    if (electric) {
      await payments.submitElectricity(
        room: widget.room!,
        amount: _amountValue,
        method: method,
        paymentPassword: form.needPassword ? password : null,
      );
    } else {
      await payments.submitCard(
        amount: _amountValue,
        method: method,
        otherStudentId: _other ? _otherId.text.trim() : null,
        returnUrl: Uri.parse(
          'https://newcard.xjit.edu.cn/#/pages_plugins/recharge/webSuccess',
        ),
      );
    }
    if (!mounted) return;
    switch (payments.state.phase) {
      case PaymentPhase.completed:
        _doneTitle = '电费充值成功';
        _donePrefix = '¥';
        _go(_Step.done);
        unawaited(_refresh());
      case PaymentPhase.awaitingExternalPayment:
        _go(_Step.pending);
        await _openPayment();
      case PaymentPhase.outcomeUnknown:
        _go(_Step.pending);
        unawaited(_refresh());
      default:
        // Failed: back to the form with the reason.
        _go(_Step.form, direction: -1);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _listen,
    builder: (context, _) {
      final submitting = payments.state.phase == PaymentPhase.submitting;
      final Widget content = switch (_step) {
        _Step.form => _buildForm(context),
        _Step.confirm => _buildConfirm(context, submitting),
        _Step.done => _buildDone(context),
        _Step.pending => _buildPending(context),
      };
      return PopScope(
        canPop: !submitting,
        child: SingleChildScrollView(
          key: const Key('recharge.scroll'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            0,
          ),
          child: AnimatedSize(
            duration: AppMotion.long,
            curve: AppMotion.emphasized,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: AppMotion.reduced(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 380),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [
                  for (final p in previous) IgnorePointer(child: p),
                  ?current,
                ],
              ),
              transitionBuilder: (child, animation) =>
                  sequentialTransition(child, animation, direction: _direction),
              child: KeyedSubtree(key: ValueKey(_step), child: content),
            ),
          ),
        ),
      );
    },
  );

  // ---- steps --------------------------------------------------------------

  Widget _buildForm(BuildContext context) {
    final title = electric ? '充值电费' : '校园卡充值';
    final state = payments.state;
    final card = payments.cardConfig.state;
    final elec = payments.electricityConfig.state;
    final loading = electric ? elec.isLoading : card.isLoading;
    final failure = electric ? elec.failure : card.failure;
    final hasConfig = electric ? elec.data != null : card.data != null;
    final header = SheetHeader(title: title, onBack: widget.onBack);

    if (!hasConfig || failure != null && !loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: AppSpacing.md),
          if (loading)
            const _FormSkeleton()
          else
            InlineFailure(
              message: failure?.message ?? '暂时无法读取充值配置',
              onRetry: _load,
            ),
          const SizedBox(height: AppSpacing.md),
        ],
      );
    }

    final form = _Form.from(
      electric: electric,
      card: card.data,
      elec: elec.data,
      selected: _selected,
      other: _other,
      otherId: _otherId.text.trim(),
    );
    // A previous top-up still waiting to be acknowledged locks the form.
    final locked = !state.canSubmit;
    final busy = locked || loading;
    final parsed = _tryAmount(_amount.text);
    final error = _error ?? (locked ? null : state.failure?.message);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: AppSpacing.sm),
        _Summary(form: form),
        if (locked) ...[
          const SizedBox(height: AppSpacing.md),
          _PendingStrip(
            amount: state.amount,
            message: state.failure?.message,
            onContinue: state.order == null ? null : _openPayment,
            onAcknowledge: _newPayment,
          ),
        ],
        if (form.tip.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          StatusBanner(tone: StatusTone.info, message: form.tip),
        ],
        if (form.canOther) ...[
          const SizedBox(height: AppSpacing.md),
          RowGroup(
            children: [
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                ),
                title: const Text('为他人充值'),
                value: _other,
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                        _other = v;
                        _error = null;
                      }),
              ),
            ],
          ),
          AnimatedSize(
            duration: AppMotion.medium,
            curve: AppMotion.emphasized,
            alignment: Alignment.topCenter,
            child: _other
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DrawnField(
                          key: const Key('recharge.other'),
                          label: '对方学号',
                          icon: Icons.person_outline_rounded,
                          placeholder: '输入学号',
                          text: _otherId.text,
                          active: _pad == _Pad.other,
                          enabled: !busy,
                          onTap: () => _togglePad(_Pad.other),
                        ),
                        _keypadFor(_Pad.other, busy),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        _Label('充值金额'),
        const SizedBox(height: AppSpacing.sm),
        _AmountGrid(
          options: form.options,
          selected: _amount.text,
          kwhFor: form.kwhFor,
          enabled: !busy,
          onSelected: (value) {
            HapticFeedback.selectionClick();
            setState(() {
              _amount.text = value;
              _error = null;
              _pad = _Pad.none;
            });
          },
        ),
        if (!form.fixedAmount) ...[
          const SizedBox(height: AppSpacing.sm + 2),
          // Drawn amount entry: no system keyboard.
          DrawnField(
            key: const Key('recharge.amount'),
            label: '其他金额',
            icon: Icons.edit_outlined,
            prefix: '¥ ',
            placeholder: '输入金额',
            text: _amount.text,
            active: _pad == _Pad.amount,
            enabled: !busy,
            hint: parsed != null && form.kwhFor(parsed) != null
                ? '约 ${form.kwhFor(parsed)} 度'
                : null,
            onTap: () => _togglePad(_Pad.amount),
          ),
          _keypadFor(_Pad.amount, busy),
        ],
        const SizedBox(height: AppSpacing.lg),
        _Label('支付方式'),
        const SizedBox(height: AppSpacing.sm),
        if (form.methods.isEmpty)
          const StatusBanner(tone: StatusTone.warning, message: '学校暂未开放可用的支付方式')
        else
          RowGroup(
            children: [
              for (final m in form.methods)
                _MethodRow(
                  method: m,
                  selected: identical(m, form.method),
                  enabled: !busy,
                  onTap: () => setState(() {
                    _selected = m;
                    _password.clear();
                    _error = null;
                  }),
                ),
            ],
          ),
        AnimatedSize(
          duration: AppMotion.medium,
          curve: AppMotion.emphasized,
          alignment: Alignment.topCenter,
          child: form.needPassword
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          left: AppSpacing.xs,
                          bottom: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                '一卡通支付密码 · 仅用于本次支付，不会保存',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      PinCells(
                        key: const Key('recharge.password'),
                        filled: _password.text.length,
                        active: _pad == _Pad.password,
                        enabled: !busy,
                        error: _error == '请输入 6 位支付密码',
                        onTap: () => _togglePad(_Pad.password),
                      ),
                      _keypadFor(_Pad.password, busy),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        AnimatedSize(
          duration: AppMotion.medium,
          curve: AppMotion.emphasized,
          alignment: Alignment.topCenter,
          child: error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: StatusBanner(
                    key: const Key('recharge.error'),
                    message: error,
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          key: const Key('recharge.submit'),
          label: parsed == null ? '下一步' : '下一步 · ¥$parsed',
          onPressed: busy || form.method == null ? null : () => _next(form),
        ),
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }

  Widget _buildConfirm(BuildContext context, bool submitting) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final form = _confirmForm!;
    final method = form.method!;
    final external = payBrandOf(method) != PayBrand.card;
    final kwh = form.kwhFor(_amountValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(
          title: electric ? '确认电费充值' : '确认校园卡充值',
          onBack: submitting ? null : () => _go(_Step.form, direction: -1),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '¥$_amountValue',
          key: const Key('recharge.confirmAmount'),
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        RowGroup(
          children: [
            _InfoRow(label: '充值到', value: form.target),
            _InfoRow(
              label: '支付方式',
              value: method.name.isEmpty ? method.code : method.name,
              leading: PayBrandIcon(brand: payBrandOf(method), size: 22),
            ),
            if (kwh != null) _InfoRow(label: '预计电量', value: '约 $kwh 度'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          external ? '将打开学校收银台付款，到账以校园卡余额为准。' : '确认后直接从校园卡余额扣款。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          key: const Key('recharge.confirm'),
          label: '确认支付',
          loading: submitting,
          loadingLabel: '正在提交…',
          onPressed: _confirm,
        ),
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }

  Widget _buildDone(BuildContext context) {
    final state = payments.state;
    final electricity = widget.campus.electricity.state.data;
    final room = state.room ?? widget.room;
    final balance = widget.campus.balance.state.data?.firstOrNull;
    final detail = electric
        ? (electricity != null && electricity.room.query == room
              ? '宿舍剩余 ${electricity.remainingElectricity.value} ${electricity.remainingElectricity.unit}'
              : (_confirmForm?.target ?? ''))
        : (balance == null ? '' : '余额 ¥${balance.balance}');
    return SizedBox(
      height: 320,
      child: PaymentSuccess(
        key: const Key('recharge.success'),
        title: _doneTitle,
        amountPrefix: _donePrefix,
        payment: DetectedPayment(
          amount: double.tryParse(_amountValue) ?? 0,
          balance: 0,
        ),
        detail: detail,
        onDone: _close,
      ),
    );
  }

  Widget _buildPending(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = StatusColors.of(context);
    final state = payments.state;
    final watching = _watching;
    final ownCard = !electric && !(state.otherStudentId?.isNotEmpty ?? false);
    final balance = widget.campus.balance.state.data?.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader(title: '等待到账'),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: ExcludeSemantics(
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: status.warningContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.hourglass_top_rounded,
                size: 30,
                color: status.onWarningContainer,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          '¥$_amountValue',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Semantics(
          liveRegion: true,
          child: Text(
            state.failure?.message ?? '付款完成后余额会自动更新，到账以校园卡余额为准。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        AnimatedSize(
          duration: AppMotion.medium,
          child: watching
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '正在查看到账…',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        // What the app currently sees, so a mismatch is visible at once.
        if (ownCard && balance != null) ...[
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '当前余额 ¥${balance.balance}',
                key: const Key('recharge.liveBalance'),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            if (state.order != null) ...[
              Expanded(
                child: AppButton(
                  key: const Key('recharge.continue'),
                  variant: AppButtonVariant.outlined,
                  label: '继续支付',
                  onPressed: _openPayment,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            // The user can always settle it; the app never waits forever.
            Expanded(
              child: AppButton(
                key: const Key('recharge.arrived'),
                label: '已到账',
                onPressed: _confirmArrived,
              ),
            ),
          ],
        ),
        Center(
          child: TextButton(
            key: const Key('recharge.close'),
            onPressed: _close,
            child: const Text('稍后再看'),
          ),
        ),
      ],
    );
  }
}

/// Sheet title row: optional back arrow, centred title, close button.

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Who is being topped up and where the account stands.
class _Summary extends StatelessWidget {
  const _Summary({required this.form});

  final _Form form;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FrostedCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '充值到',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: AppMotion.medium,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: AlignmentDirectional.centerStart,
                      children: [...previous, ?current],
                    ),
                    child: Text(
                      form.target,
                      key: ValueKey(form.target),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (form.stats.isNotEmpty)
                    Text(
                      form.stats.map((s) => '${s.$1} ${s.$2}').join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  form.headlineLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  form.headline,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A previous top-up not yet seen on the account.
class _PendingStrip extends StatelessWidget {
  const _PendingStrip({
    required this.amount,
    required this.message,
    required this.onContinue,
    required this.onAcknowledge,
  });

  final String? amount;
  final String? message;
  final VoidCallback? onContinue;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = StatusColors.of(context);
    return Container(
      key: const Key('recharge.pending'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: status.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            amount == null ? '上一笔充值尚未确认到账' : '上一笔充值 ¥$amount 尚未确认到账',
            style: theme.textTheme.titleSmall?.copyWith(
              color: status.onWarningContainer,
            ),
          ),
          Text(
            message ?? '到账以校园卡余额为准，确认后再开始新的充值。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: status.onWarningContainer,
            ),
          ),
          Wrap(
            children: [
              if (onContinue != null)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: status.onWarningContainer,
                  ),
                  onPressed: onContinue,
                  child: const Text('继续支付'),
                ),
              TextButton(
                key: const Key('recharge.acknowledge'),
                style: TextButton.styleFrom(
                  foregroundColor: status.onWarningContainer,
                ),
                onPressed: onAcknowledge,
                child: const Text('已到账，开始新充值'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.leading});

  final String label, value;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: AppSpacing.sm),
                ],
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Form model and pieces

/// Normalised "50.00", or null when the text is not a valid amount.
String? _tryAmount(String text) {
  try {
    return MoneyAmount.parse(text).value;
  } on CampusFailure {
    return null;
  }
}

class _Form {
  _Form({
    required this.target,
    required this.options,
    required this.methods,
    required this.method,
    required this.needPassword,
    required this.fixedAmount,
    required this.canOther,
    required this.tip,
    required this.headline,
    required this.headlineLabel,
    required this.stats,
    required this.price,
  });

  factory _Form.from({
    required bool electric,
    required CardRechargeConfig? card,
    required ElectricityRechargeConfig? elec,
    required PayMethod? selected,
    required bool other,
    required String otherId,
  }) {
    final methods = electric ? elec!.payMethods : card!.payMethods;
    final method =
        methods
            .where(
              (m) =>
                  m.code == selected?.code &&
                  m.tradeType == selected?.tradeType,
            )
            .firstOrNull ??
        methods.firstOrNull;
    if (electric) {
      final room = elec!.room;
      final name = [
        room.buildingName,
        room.roomName,
      ].where((s) => s.isNotEmpty).join(' · ');
      return _Form(
        target: name.isEmpty ? room.query : name,
        options: elec.amountOptions,
        methods: methods,
        method: method,
        needPassword: method?.code == '06' && elec.needPaymentPassword,
        fixedAmount: elec.amtInputDisabled,
        canOther: false,
        tip: elec.tip,
        headline:
            '${elec.remainingElectricity.value} ${elec.remainingElectricity.unit}',
        headlineLabel: '剩余电量',
        stats: [
          ('电价', '${elec.price.value} ${elec.price.unit}'),
          ('卡余额', '¥${elec.cardBalance.value}'),
        ],
        price: elec.price.numericValue,
      );
    }
    return _Form(
      target: other
          ? (otherId.isEmpty ? '同学的校园卡' : '学号 $otherId')
          : [card!.name, card.studentId].where((s) => s.isNotEmpty).join(' · '),
      options: card!.amountOptions,
      methods: methods,
      method: method,
      needPassword: false,
      fixedAmount: false,
      canOther: card.canPayOther,
      tip: '',
      headline: '¥${card.balance}',
      headlineLabel: '当前余额',
      stats: const [],
      price: null,
    );
  }

  final String target;
  final List<AmountOption> options;
  final List<PayMethod> methods;
  final PayMethod? method;
  final bool needPassword, fixedAmount, canOther;
  final String tip, headline, headlineLabel;
  final List<(String, String)> stats;
  final double? price;

  /// Rough kWh for an amount at the current price ("约" in the UI).
  String? kwhFor(String amount) {
    final p = price;
    final a = double.tryParse(amount);
    if (p == null || p <= 0 || a == null) return null;
    return (a / p).toStringAsFixed(0);
  }
}

class _AmountGrid extends StatelessWidget {
  const _AmountGrid({
    required this.options,
    required this.selected,
    required this.kwhFor,
    required this.enabled,
    required this.onSelected,
  });

  final List<AmountOption> options;
  final String selected;
  final String? Function(String) kwhFor;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        const gap = AppSpacing.sm;
        final columns = c.maxWidth < 300 ? 2 : 3;
        final width = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final option in options)
              SizedBox(
                width: width,
                child: _AmountTile(
                  amount: option.amount,
                  hint: kwhFor(option.amount),
                  selected: _tryAmount(selected) == _tryAmount(option.amount),
                  enabled: enabled,
                  onTap: () => onSelected(option.amount),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AmountTile extends StatelessWidget {
  const _AmountTile({
    required this.amount,
    required this.hint,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String amount;
  final String? hint;
  final bool selected, enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Semantics(
      button: true,
      selected: selected,
      label: '¥$amount${hint == null ? '' : '，约 $hint 度'}',
      excludeSemantics: true,
      child: PressScale(
        enabled: enabled,
        child: FrostedCard(
          radius: AppRadius.lg,
          fill: selected
              ? scheme.primary.withValues(alpha: dark ? 0.22 : 0.1)
              : null,
          edge: selected ? BorderSide(color: scheme.primary, width: 1.5) : null,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 58),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '¥$amount',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected ? scheme.primary : scheme.onSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (hint != null)
                      Text(
                        '约 $hint 度',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: selected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.method,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final PayMethod method;
  final bool selected, enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final brand = payBrandOf(method);
    final name = method.name.isEmpty ? method.code : method.name;
    final note = brand == PayBrand.card ? '从校园卡余额扣款' : '跳转学校收银台付款';
    return Semantics(
      button: true,
      selected: selected,
      label: '$name，$note',
      excludeSemantics: true,
      child: InkWell(
        key: Key('recharge.method.${method.code}'),
        onTap: enabled ? onTap : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                PayBrandIcon(brand: brand, size: 34),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: theme.textTheme.titleSmall),
                      Text(
                        note,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AnimatedContainer(
                  duration: AppMotion.medium,
                  curve: AppMotion.curve,
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? scheme.primary : Colors.transparent,
                    border: Border.all(
                      color: selected ? scheme.primary : scheme.outline,
                      width: 1.5,
                    ),
                  ),
                  child: AnimatedOpacity(
                    duration: AppMotion.short,
                    opacity: selected ? 1 : 0,
                    child: Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FormSkeleton extends StatelessWidget {
  const _FormSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '正在读取充值配置',
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Skeleton(height: 72, radius: AppRadius.lg),
          SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(child: Skeleton(height: 58, radius: AppRadius.lg)),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: Skeleton(height: 58, radius: AppRadius.lg)),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: Skeleton(height: 58, radius: AppRadius.lg)),
            ],
          ),
          SizedBox(height: AppSpacing.lg),
          Skeleton(height: 116, radius: AppRadius.lg),
        ],
      ),
    );
  }
}
