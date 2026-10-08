import 'package:flutter/material.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/status_banner.dart';
import '../../../shared/widgets/top_sheet.dart';
import 'accent_panel.dart';
import 'campus_format.dart';
import 'quick_entries.dart';
import 'recharge_sheet.dart';
import 'room_keypad.dart';
import 'section_parts.dart';
import 'signed_in_memo.dart';

/// Dorm electricity as a sheet dropping from the top: the reading, room
/// change and top-up all happen inside it.
Future<void> showElectricitySheet(
  BuildContext context, {
  required CampusController campus,
  required AuthController auth,
  Widget Function(PaymentResult)? paymentBuilder,
}) => showTopSheet<void>(
  context,
  builder: (_) => ElectricitySheet(
    campus: campus,
    auth: auth,
    paymentBuilder: paymentBuilder,
  ),
);

enum _View { reading, room, recharge }

class ElectricitySheet extends StatefulWidget {
  const ElectricitySheet({
    super.key,
    required this.campus,
    required this.auth,
    this.paymentBuilder,
  });

  final CampusController campus;
  final AuthController auth;
  final Widget Function(PaymentResult)? paymentBuilder;

  @override
  State<ElectricitySheet> createState() => _ElectricitySheetState();
}

class _ElectricitySheetState extends State<ElectricitySheet> {
  late final Listenable _listenable = Listenable.merge([
    widget.auth,
    widget.campus.electricity,
  ]);
  final _memo = SignedInMemo<ResourceState<ElectricityAccount>>();
  late var _view = widget.campus.roomQuery == null ? _View.room : _View.reading;
  var _direction = 1;

  CampusController get campus => widget.campus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await campus.restorePreferences();
      if (!mounted) return;
      final room = campus.roomQuery;
      if (room != null) {
        if (_view == _View.room) _go(_View.reading);
        await campus.loadElectricity(room);
      }
    });
  }

  void _go(_View view, {int direction = 1}) {
    if (!mounted) return;
    setState(() {
      _direction = direction;
      _view = view;
    });
  }

  Future<void> _submitRoom(String room) async {
    _go(_View.reading);
    await campus.loadElectricity(room, refresh: true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _listenable,
    builder: (context, _) {
      final state = _memo.read(
        signedIn: widget.auth.state.isAuthenticated,
        live: () => campus.electricity.state,
      );
      final Widget content = switch (_view) {
        _View.reading => _reading(context, state),
        _View.room => _RoomForm(
          initial: campus.roomQuery,
          onBack: campus.roomQuery == null
              ? null
              : () => _go(_View.reading, direction: -1),
          onSubmit: _submitRoom,
        ),
        _View.recharge => RechargeFlow(
          campus: campus,
          room: state.data?.room.query ?? campus.roomQuery,
          paymentBuilder: widget.paymentBuilder,
          onBack: () => _go(_View.reading, direction: -1),
        ),
      };
      // The recharge flow scrolls itself; the other views are short.
      final body = _view == _View.recharge
          ? content
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                0,
              ),
              child: content,
            );
      return AnimatedSize(
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
          child: KeyedSubtree(key: ValueKey(_view), child: body),
        ),
      );
    },
  );

  Widget _reading(BuildContext context, ResourceState<ElectricityAccount> s) {
    final data = s.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetHeader(title: '宿舍电费'),
        const SizedBox(height: AppSpacing.sm),
        if (data != null)
          _ReadingPanel(
            account: data,
            refreshing: s.isRefreshing,
            onRecharge: () => _go(_View.recharge),
            onChangeRoom: () => _go(_View.room),
          )
        else if (s.failure != null && !s.isLoading) ...[
          InlineFailure(
            message: s.failure!.message,
            onRetry: () {
              final room = campus.roomQuery;
              if (room != null) campus.loadElectricity(room, refresh: true);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const Key('electricity.room'),
            variant: AppButtonVariant.outlined,
            icon: Icons.swap_horiz_rounded,
            label: '更换宿舍',
            onPressed: () => _go(_View.room),
          ),
        ] else
          Semantics(
            label: '正在查询电量',
            child: const Skeleton(height: 196, radius: AppRadius.xl),
          ),
        if (data != null && s.isStale) ...[
          const SizedBox(height: AppSpacing.sm),
          StaleNote(
            text: '${updatedText(s.updatedAt, DateTime.now())} · 电量刷新失败',
          ),
        ],
        if (campus.roomStorageError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          StatusBanner(
            tone: StatusTone.warning,
            message: campus.roomStorageError!,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _ReadingPanel extends StatelessWidget {
  const _ReadingPanel({
    required this.account,
    required this.refreshing,
    required this.onRecharge,
    required this.onChangeRoom,
  });

  final ElectricityAccount account;
  final bool refreshing;
  final VoidCallback onRecharge;
  final VoidCallback onChangeRoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final room = account.room;
    final quantity = account.remainingElectricity;
    final value = quantity.numericValue;
    final low = value != null && value < lowElectricityThreshold;
    final title = [
      room.buildingName,
      room.roomName,
    ].where((s) => s.isNotEmpty).join(' · ');

    return AccentPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.isEmpty ? room.query : title,
                  style: onAccent(
                    context,
                    theme.textTheme.titleMedium,
                  )?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              // Only built while refreshing, so it never animates hidden.
              AnimatedSwitcher(
                duration: AppMotion.medium,
                child: refreshing
                    ? SizedBox.square(
                        key: const ValueKey('refreshing'),
                        dimension: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary.withValues(alpha: 0.85),
                          semanticsLabel: '正在更新电量',
                        ),
                      )
                    : const SizedBox.square(dimension: 14),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '剩余电量',
            style: onAccent(context, theme.textTheme.bodySmall, 0.78),
          ),
          CountUpText(
            key: const Key('electricity.value'),
            value: value,
            fallback: quantity.value,
            suffix: ' ${quantity.unit}',
            style: onAccent(
              context,
              theme.textTheme.displaySmall,
            )?.copyWith(fontWeight: FontWeight.w700, height: 1.1),
            suffixStyle: onAccent(context, theme.textTheme.titleMedium, 0.85),
          ),
          if (low) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.onPrimary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 15,
                    color: scheme.onPrimary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      '电量偏低，建议尽快充值',
                      style: onAccent(
                        context,
                        theme.textTheme.labelMedium,
                      )?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              _PanelButton(
                key: const Key('electricity.recharge'),
                icon: Icons.bolt_rounded,
                label: '充值电费',
                filled: true,
                onTap: onRecharge,
              ),
              _PanelButton(
                key: const Key('electricity.room'),
                icon: Icons.swap_horiz_rounded,
                label: '更换宿舍',
                filled: false,
                onTap: onChangeRoom,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    super.key,
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressScale(
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: filled
              ? scheme.onPrimary
              : scheme.onPrimary.withValues(alpha: 0.16),
          foregroundColor: filled ? scheme.primary : scheme.onPrimary,
          minimumSize: const Size(0, AppSizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl - 4),
          shape: const StadiumBorder(),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }
}

class _RoomForm extends StatelessWidget {
  const _RoomForm({
    required this.initial,
    required this.onBack,
    required this.onSubmit,
  });

  final String? initial;
  final VoidCallback? onBack;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetHeader(title: initial == null ? '设置宿舍' : '更换宿舍', onBack: onBack),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '用于查询剩余电量和充值电费。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Drawn keypad: the system keyboard never opens over the sheet.
        RoomKeypadForm(initial: initial, onSubmit: onSubmit),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}
