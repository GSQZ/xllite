import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/top_sheet.dart';
import 'payment_success.dart';
import 'payment_watch.dart';
import 'qr_view.dart';

/// Drops the payment code down from the top of the screen.
Future<void> showCampusCodeSheet(
  BuildContext context, {
  required CampusController campus,
}) => showTopSheet<void>(
  context,
  builder: (_) => CampusCodeSheet(campus: campus),
);

/// Campus payment code. The credential exists only while this sheet is on
/// screen and the app is in the foreground: the controller drops it when
/// the sheet closes or the app goes to the background, and fetches a fresh
/// one when it expires. Only [CampusCodeController.usableCode] is drawn.
///
/// Every state (loading, ready, failed) uses the same three rows: a caption
/// line, a fixed-size code tile and one status line. Only their contents
/// cross-fade, so the sheet never changes height.
class CampusCodeSheet extends StatefulWidget {
  const CampusCodeSheet({super.key, required this.campus});

  final CampusController campus;

  @override
  State<CampusCodeSheet> createState() => _CampusCodeSheetState();
}

class _CampusCodeSheetState extends State<CampusCodeSheet>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Timer? _ticker;
  late final _watch = PaymentWatch(widget.campus);
  CampusCode? _shown;

  /// Remaining validity, swept linearly from 1 to 0 for each new code.
  late final _ring = AnimationController(vsync: this);

  CampusCodeController get _code => widget.campus.campusCode;

  // Scanners read dark-on-white best, so the tile stays white in dark mode.
  static const _paper = Color(0xFFFFFFFF);
  static const _ink = Color(0xFF15171C);

  @override
  void initState() {
    super.initState();
    _code.addListener(_onCode);
    _watch.addListener(_onPaid);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _code.setVisible(true);
      _watch.start();
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _shown != null) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _watch.setPaused(state != AppLifecycleState.resumed);
  }

  void _onPaid() {
    // Paid: the credential is no longer needed on screen.
    if (_watch.payment != null) _code.setVisible(false);
    setState(() {});
  }

  void _onCode() {
    final code = _code.usableCode;
    if (identical(code, _shown)) return;
    _shown = code;
    if (code == null) {
      _ring.stop();
      _ring.value = 0;
      return;
    }
    final left = code.expiresAt.difference(DateTime.now());
    _ring.value = 1;
    if (left > Duration.zero) _ring.animateTo(0, duration: left);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watch.removeListener(_onPaid);
    _watch.dispose();
    _code.removeListener(_onCode);
    _ring.dispose();
    _ticker?.cancel();
    // Deferred: the controller notifies, and the tree is being torn down.
    final code = _code;
    scheduleMicrotask(() => code.setVisible(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = AppSpacing.gutterFor(constraints.maxWidth);
        final qrSize = math.min(196.0, constraints.maxWidth - gutter * 2 - 24);
        return ListenableBuilder(
          listenable: _code,
          builder: (context, _) {
            final state = _code.state;
            final code = _code.usableCode;
            final failure = code == null && !state.isLoading
                ? state.failure
                : null;
            final paid = _watch.payment;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xs, gutter, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(code: code, paid: paid != null),
                  const SizedBox(height: AppSpacing.md),
                  // The success view takes exactly the code's place, so the
                  // sheet keeps its height.
                  Stack(
                    children: [
                      AnimatedOpacity(
                        opacity: paid == null ? 1 : 0,
                        duration: AppMotion.short,
                        child: IgnorePointer(
                          ignoring: paid != null,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: _Tile(
                                  size: qrSize,
                                  paper: _paper,
                                  child: code != null
                                      ? QrView(
                                          key: ValueKey(code.expiresAt),
                                          data: code.value,
                                          size: qrSize,
                                          color: _ink,
                                        )
                                      : Icon(
                                          Icons.qr_code_2_rounded,
                                          key: ValueKey(failure == null),
                                          size: 72,
                                          color: failure == null
                                              ? const Color(0x1A000000)
                                              : const Color(0x33000000),
                                        ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _StatusLine(
                                code: code,
                                failure: failure,
                                ring: _ring,
                                onRefresh: _code.refresh,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (paid != null)
                        Positioned.fill(
                          child: PaymentSuccess(
                            key: const Key('paid'),
                            payment: paid,
                            onDone: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.code, required this.paid});

  final CampusCode? code;
  final bool paid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = code;
    final who = c != null && c.displayInfo
        ? [c.name, c.studentId].where((s) => s.isNotEmpty).join(' · ')
        : '';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text('付款码', style: theme.textTheme.titleMedium),
              ),
              // Always one line, so the header height never changes.
              AnimatedSwitcher(
                duration: AppMotion.medium,
                layoutBuilder: (current, previous) => Stack(
                  alignment: AlignmentDirectional.centerStart,
                  children: [...previous, ?current],
                ),
                child: Text(
                  paid
                      ? '已完成支付'
                      : who.isEmpty
                      ? '向收银员出示此码'
                      : who,
                  key: ValueKey((who, paid)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '关闭',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

/// White rounded tile of a fixed size; its contents cross-fade.
class _Tile extends StatelessWidget {
  const _Tile({required this.size, required this.paper, required this.child});

  final double size;
  final Color paper;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '付款码二维码',
      image: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(AppRadius.lg + 4),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: SizedBox.square(
          dimension: size,
          child: AnimatedSwitcher(
            duration: AppMotion.medium,
            switchInCurve: AppMotion.curve,
            switchOutCurve: AppMotion.exit,
            child: Center(key: child.key, child: child),
          ),
        ),
      ),
    );
  }
}

/// One fixed-height line: progress while loading, countdown and balance
/// when ready, the reason and a retry when it failed.
class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.code,
    required this.failure,
    required this.ring,
    required this.onRefresh,
  });

  final CampusCode? code;
  final CampusFailure? failure;
  final Animation<double> ring;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final c = code;

    final Widget leading;
    final String text;
    final Widget? action;
    final Object key;
    if (c != null) {
      final left = c.expiresAt.difference(DateTime.now());
      final seconds = math.max(0, (left.inMilliseconds / 1000).ceil());
      leading = AnimatedBuilder(
        animation: ring,
        builder: (context, _) => CircularProgressIndicator(
          value: ring.value,
          strokeWidth: 2.2,
          color: scheme.primary,
          backgroundColor: scheme.primary.withValues(alpha: 0.14),
        ),
      );
      text = [
        '$seconds 秒后刷新',
        if (c.displayBalance && c.balance.isNotEmpty) '余额 ¥${c.balance}',
      ].join(' · ');
      action = TextButton(onPressed: onRefresh, child: const Text('刷新'));
      key = 'ready';
    } else if (failure != null) {
      leading = Icon(
        Icons.error_outline_rounded,
        size: 16,
        color: scheme.error,
      );
      text = failure!.message;
      action = TextButton(
        key: const Key('code.retry'),
        onPressed: onRefresh,
        child: const Text('重试'),
      );
      key = 'failure';
    } else {
      leading = const CircularProgressIndicator(strokeWidth: 2.2);
      text = '正在获取付款码…';
      action = null;
      key = 'loading';
    }

    return SizedBox(
      height: AppSizes.touchTarget,
      child: AnimatedSwitcher(
        duration: AppMotion.medium,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.center,
          children: [...previous, ?current],
        ),
        child: Row(
          key: ValueKey(key),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(dimension: 16, child: leading),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                text,
                key: c != null ? const Key('code.countdown') : null,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: failure != null && c == null
                    ? muted?.copyWith(color: scheme.error)
                    : muted,
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: AppSpacing.xs),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
