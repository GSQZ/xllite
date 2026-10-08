import 'package:flutter/material.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/frosted.dart';
import '../../../shared/widgets/expand_route.dart';
import '../../../shared/widgets/motion.dart';

/// Values the entry grid displays, captured by the home tab.
class QuickEntryData {
  const QuickEntryData({
    required this.exams,
    required this.upcomingExamCount,
    required this.undatedExamCount,
    required this.balance,
    required this.electricity,
    required this.room,
  });

  final ResourceState<List<Exam>> exams;
  final int upcomingExamCount;
  final int undatedExamCount;
  final ResourceState<List<CardAccount>> balance;
  final ResourceState<ElectricityAccount> electricity;
  final String? room;
}

/// Below this many kWh the electricity value turns amber.
const lowElectricityThreshold = 10.0;

/// Fill of an entry tile; the expanding page starts from this colour.
Color entryTileColor(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return Theme.of(context).brightness == Brightness.dark
      ? scheme.surfaceContainerLow
      : scheme.surfaceContainerLowest;
}

/// 2 × 2 grid: 成绩 / 考试 / 校园卡 / 宿舍电量. The first three grow into
/// their pages when tapped. Each tile is wrapped by [wrap] so the caller can
/// stagger their entrance.
class QuickEntries extends StatelessWidget {
  const QuickEntries({
    super.key,
    required this.data,
    required this.gradesPage,
    required this.examsPage,
    required this.cardPage,
    required this.onElectricity,
    required this.wrap,
    this.onPageOpen,
    this.onPageClosed,
  });

  final QuickEntryData data;
  final WidgetBuilder gradesPage;
  final WidgetBuilder examsPage;
  final WidgetBuilder cardPage;
  final VoidCallback onElectricity;
  final Widget Function(int index, Widget tile) wrap;
  final VoidCallback? onPageOpen;
  final VoidCallback? onPageClosed;

  Widget _expanding(
    BuildContext context, {
    required WidgetBuilder page,
    required Widget Function(VoidCallback open) tile,
  }) => ExpandOnTap(
    closedColor: entryTileColor(context),
    closedRadius: AppRadius.lg + 4,
    onOpen: onPageOpen,
    onClosed: onPageClosed,
    closedBuilder: (context, open) => tile(open),
    openBuilder: page,
  );

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _expanding(
        context,
        page: gradesPage,
        tile: (open) => _EntryTile(
          key: const Key('entry.grades'),
          icon: Icons.school_outlined,
          hue: EntryHue.blue,
          title: '成绩',
          value: const _Caption('成绩与绩点'),
          onTap: open,
        ),
      ),
      _expanding(
        context,
        page: examsPage,
        tile: (open) => _EntryTile(
          key: const Key('entry.exams'),
          icon: Icons.edit_calendar_outlined,
          hue: EntryHue.indigo,
          title: '考试',
          value: _examValue(context),
          onTap: open,
        ),
      ),
      _expanding(
        context,
        page: cardPage,
        tile: (open) => _EntryTile(
          key: const Key('entry.card'),
          icon: Icons.account_balance_wallet_outlined,
          hue: EntryHue.teal,
          title: '校园卡',
          value: _balanceValue(context),
          onTap: open,
        ),
      ),
      // Opens the electricity sheet (asks for the room first if unset).
      _electricityTile(context, onElectricity),
    ];
    Widget row(int a, int b) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: wrap(a, tiles[a])),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: wrap(b, tiles[b])),
        ],
      ),
    );
    return Column(
      children: [
        row(0, 1),
        const SizedBox(height: AppSpacing.md),
        row(2, 3),
      ],
    );
  }

  Widget _electricityTile(BuildContext context, VoidCallback onTap) =>
      _EntryTile(
        key: const Key('entry.electricity'),
        icon: Icons.bolt_rounded,
        hue: EntryHue.amber,
        title: '宿舍电量',
        value: _electricityValue(context),
        caption: data.electricity.data?.room.query ?? data.room,
        onTap: onTap,
      );

  Widget _examValue(BuildContext context) {
    final exams = data.exams;
    if (!exams.hasData) {
      if (exams.failure != null && !exams.isLoading) {
        return const _Caption('暂不可用');
      }
      return const _ValueSkeleton();
    }
    if (data.upcomingExamCount > 0) {
      return _Emphasis(text: '${data.upcomingExamCount}', suffix: ' 场待考');
    }
    if (data.undatedExamCount > 0) {
      return _Caption('${data.undatedExamCount} 场时间待定');
    }
    return const _Caption('暂无安排');
  }

  Widget _balanceValue(BuildContext context) {
    final balance = data.balance;
    final accounts = balance.data;
    if (accounts == null) {
      if (balance.failure != null && !balance.isLoading) {
        return const _Caption('暂不可用');
      }
      return const _ValueSkeleton();
    }
    if (accounts.isEmpty) return const _Caption('无账户信息');
    // Different account types are never summed; the first is the main wallet.
    final main = accounts.first;
    return _Number(
      value: double.tryParse(main.balance.trim()),
      raw: main.balance,
      prefix: '¥',
    );
  }

  Widget _electricityValue(BuildContext context) {
    final power = data.electricity;
    if (data.room == null) {
      return Text(
        '设置宿舍',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    final account = power.data;
    if (account == null) {
      if (power.failure != null && !power.isLoading) {
        return const _Caption('查询失败');
      }
      return const _ValueSkeleton();
    }
    final quantity = account.remainingElectricity;
    final value = quantity.numericValue;
    final low = value != null && value < lowElectricityThreshold;
    return _Number(
      value: value,
      raw: quantity.value,
      suffix: ' ${quantity.unit}',
      color: low ? StatusColors.of(context).warning : null,
      badge: low ? '偏低' : null,
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    super.key,
    required this.icon,
    required this.hue,
    required this.title,
    required this.value,
    required this.onTap,
    this.caption,
  });

  final IconData icon;
  final EntryHue hue;
  final String title;
  final Widget value;
  final String? caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final tint = hue.of(context);
    final radius = BorderRadius.circular(AppRadius.lg + 4);
    return PressScale(
      child: FrostedCard(
        radius: radius.topLeft.x,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg - 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: tint.withValues(alpha: dark ? 0.22 : 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Icon(icon, size: 20, color: tint),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm + 2),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                AnimatedSwitcher(
                  duration: AppMotion.medium,
                  switchInCurve: AppMotion.curve,
                  switchOutCurve: AppMotion.exit,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: AlignmentDirectional.centerStart,
                    children: [...previous, ?current],
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(value.runtimeType),
                    child: value,
                  ),
                ),
                if (caption != null && caption!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _Emphasis extends StatelessWidget {
  const _Emphasis({required this.text, this.suffix = ''});

  final String text;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text, style: _numberStyle(theme)),
          TextSpan(
            text: suffix,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

TextStyle? _numberStyle(ThemeData theme, [Color? color]) =>
    theme.textTheme.titleLarge?.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: color ?? theme.colorScheme.onSurface,
    );

class _Number extends StatelessWidget {
  const _Number({
    required this.value,
    required this.raw,
    this.prefix = '',
    this.suffix = '',
    this.color,
    this.badge,
  });

  final double? value;
  final String raw;
  final String prefix;
  final String suffix;
  final Color? color;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = CountUpText(
      value: value,
      fallback: raw,
      prefix: prefix,
      suffix: suffix,
      style: _numberStyle(theme, color),
      suffixStyle: theme.textTheme.bodySmall?.copyWith(
        color: color ?? theme.colorScheme.onSurfaceVariant,
      ),
    );
    if (badge == null) return number;
    return Row(
      children: [
        Flexible(child: number),
        const SizedBox(width: AppSpacing.xs + 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: StatusColors.of(context).warningContainer,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            badge!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: StatusColors.of(context).onWarningContainer,
            ),
          ),
        ),
      ],
    );
  }
}

class _ValueSkeleton extends StatelessWidget {
  const _ValueSkeleton();

  @override
  Widget build(BuildContext context) =>
      const Skeleton(width: 72, height: 22, radius: AppRadius.sm);
}
