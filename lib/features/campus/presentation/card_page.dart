import 'package:flutter/material.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/state_panel.dart';
import 'accent_panel.dart';
import 'campus_code_sheet.dart';
import 'campus_format.dart';
import 'detail_sheet.dart';
import 'feature_page.dart';
import 'section_parts.dart';
import 'signed_in_memo.dart';
import 'recharge_sheet.dart';

/// Date ranges offered for transactions. "近期" leaves the range to the
/// school system's default; the others are whole calendar months.
enum TransactionRange { recent, thisMonth, lastMonth }

extension on TransactionRange {
  String get label => switch (this) {
    TransactionRange.recent => '近期',
    TransactionRange.thisMonth => '本月',
    TransactionRange.lastMonth => '上月',
  };

  TransactionQuery query(DateTime now) {
    final today = campusNow(now);
    final first = DateTime.utc(today.year, today.month);
    return switch (this) {
      TransactionRange.recent => const TransactionQuery(),
      TransactionRange.thisMonth => TransactionQuery(
        fromDate: first,
        toDate: DateTime.utc(today.year, today.month, today.day),
      ),
      TransactionRange.lastMonth => TransactionQuery(
        fromDate: DateTime.utc(today.year, today.month - 1),
        toDate: first.subtract(const Duration(days: 1)),
      ),
    };
  }
}

class CardPage extends StatefulWidget {
  const CardPage({super.key, required this.auth, required this.campus});

  final AuthController auth;
  final CampusController campus;

  @override
  State<CardPage> createState() => _CardPageState();
}

class _CardView {
  const _CardView(this.balance, this.transactions);
  final ResourceState<List<CardAccount>> balance;
  final TransactionsState transactions;
}

class _CardPageState extends State<CardPage> {
  late final Listenable _listenable = Listenable.merge([
    widget.auth,
    widget.campus.balance,
    widget.campus.transactions,
  ]);
  final _memo = SignedInMemo<_CardView>();
  var _range = TransactionRange.recent;

  CampusController get _campus => widget.campus;

  @override
  void initState() {
    super.initState();
    _range = _rangeOf(_campus.transactions.query);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _campus.loadBalance();
      if (!_campus.transactions.state.hasLoaded) _campus.transactions.load();
    });
  }

  TransactionRange _rangeOf(TransactionQuery query) {
    final now = DateTime.now();
    for (final range in TransactionRange.values) {
      final q = range.query(now);
      if (q.fromDate == query.fromDate && q.toDate == query.toDate) {
        return range;
      }
    }
    return TransactionRange.recent;
  }

  void _select(TransactionRange range) {
    if (range == _range) return;
    setState(() => _range = range);
    _campus.transactions.load(query: range.query(DateTime.now()));
  }

  Future<void> _refresh() => Future.wait([
    _campus.loadBalance(refresh: true),
    _campus.transactions.load(),
  ]);

  void _nearEnd() {
    final s = _campus.transactions.state;
    if (s.hasMore && !s.isLoading && s.failure == null) {
      _campus.transactions.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _listenable,
      builder: (context, _) {
        final view = _memo.read(
          signedIn: widget.auth.state.isAuthenticated,
          live: () =>
              _CardView(_campus.balance.state, _campus.transactions.state),
        );
        return FeaturePage(
          title: '校园卡',
          scrollKey: const Key('card.scroll'),
          onRefresh: _refresh,
          onNearEnd: _nearEnd,
          children: [
            _BalancePanel(
              state: view.balance,
              campus: _campus,
              onRetry: () => _campus.loadBalance(),
            ),
            if (view.balance.isStale) ...[
              const SizedBox(height: AppSpacing.md),
              StaleNote(
                text:
                    '${updatedText(view.balance.updatedAt, DateTime.now())} · 余额刷新失败，下拉重试',
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            const SectionHeader(title: '交易记录'),
            const SizedBox(height: AppSpacing.sm),
            ChoicePills<TransactionRange>(
              key: const Key('card.ranges'),
              options: TransactionRange.values,
              selected: _range,
              label: (r) => r.label,
              onSelected: _select,
            ),
            const SizedBox(height: AppSpacing.lg),
            ..._transactions(context, view.transactions),
          ],
        );
      },
    );
  }

  List<Widget> _transactions(BuildContext context, TransactionsState s) {
    final theme = Theme.of(context);
    if (!s.hasLoaded) {
      if (s.failure != null && !s.isLoading) {
        return [
          InlineFailure(
            message: s.failure!.message,
            onRetry: () => _campus.transactions.load(),
          ),
        ];
      }
      return const [_TransactionsSkeleton()];
    }
    if (s.items.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.only(top: AppSpacing.xl),
          child: StatePanel(
            icon: Icons.receipt_long_outlined,
            title: '这段时间没有交易记录',
          ),
        ),
      ];
    }

    // Group by day, keeping the school system's order.
    final groups = <String, List<CardTransaction>>{};
    final labels = <String, String>{};
    for (final t in s.items) {
      final at = parseSchoolTimestamp(t.date);
      final key = at == null ? '' : '${at.year}-${at.month}-${at.day}';
      groups.putIfAbsent(key, () => []).add(t);
      labels[key] = at == null ? '其他' : civilDateText(at);
    }

    return [
      for (final entry in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.sm,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            labels[entry.key]!,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        RowGroup(
          children: [for (final t in entry.value) _TransactionRow(item: t)],
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      _ListFooter(state: s, onRetry: () => _campus.transactions.loadMore()),
    ];
  }
}

class _BalancePanel extends StatelessWidget {
  const _BalancePanel({
    required this.state,
    required this.campus,
    required this.onRetry,
  });

  final ResourceState<List<CardAccount>> state;
  final CampusController campus;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accounts = state.data;
    final main = accounts?.firstOrNull;

    final Widget amount;
    if (main != null) {
      amount = CountUpText(
        key: const Key('card.balance'),
        value: double.tryParse(main.balance.trim()),
        fallback: main.balance,
        prefix: '¥',
        style: onAccent(
          context,
          theme.textTheme.displaySmall,
        )?.copyWith(fontWeight: FontWeight.w700, height: 1.1),
      );
    } else if (accounts != null) {
      amount = Text(
        '无账户信息',
        style: onAccent(context, theme.textTheme.titleLarge),
      );
    } else if (state.failure != null && !state.isLoading) {
      amount = Row(
        children: [
          Flexible(
            child: Text(
              state.failure!.message,
              style: onAccent(context, theme.textTheme.bodyMedium),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: scheme.onPrimary),
            onPressed: onRetry,
            child: const Text('重试'),
          ),
        ],
      );
    } else {
      amount = Skeleton(
        width: 160,
        height: 40,
        color: scheme.onPrimary.withValues(alpha: 0.22),
      );
    }

    return AccentPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            main == null || main.typeName.isEmpty
                ? '账户余额'
                : '${main.typeName} · 余额',
            style: onAccent(context, theme.textTheme.bodyMedium, 0.85),
          ),
          const SizedBox(height: AppSpacing.xs),
          AnimatedSwitcher(duration: AppMotion.medium, child: amount),
          // Other account types are listed, never added together.
          if (accounts != null && accounts.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            for (final a in accounts.skip(1))
              Text(
                '${a.typeName.isEmpty ? '其他账户' : a.typeName}  ¥${a.balance}',
                style: onAccent(context, theme.textTheme.bodySmall, 0.85),
              ),
          ],
          const SizedBox(height: AppSpacing.xl - 4),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              _CodeButton(
                onTap: () => showCampusCodeSheet(context, campus: campus),
              ),
              // Grows out of the button, like the home entries.
              // Drops from the top, like the payment code.
              _RechargeButton(
                onTap: () => showRechargeSheet(context, campus: campus),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RechargeButton extends StatelessWidget {
  const _RechargeButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressScale(
      child: FilledButton.icon(
        key: const Key('card.recharge'),
        style: FilledButton.styleFrom(
          backgroundColor: scheme.onPrimary.withValues(alpha: 0.16),
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, AppSizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl - 4),
          shape: const StadiumBorder(),
        ),
        onPressed: onTap,
        icon: const Icon(Icons.add_rounded),
        label: const Text('充值'),
      ),
    );
  }
}

class _CodeButton extends StatelessWidget {
  const _CodeButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressScale(
      child: FilledButton.icon(
        key: const Key('card.code'),
        style: FilledButton.styleFrom(
          backgroundColor: scheme.onPrimary,
          foregroundColor: scheme.primary,
          minimumSize: const Size(0, AppSizes.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl - 4),
          shape: const StadiumBorder(),
        ),
        onPressed: onTap,
        icon: const Icon(Icons.qr_code_2_rounded),
        label: const Text('付款码'),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.item});

  final CardTransaction item;

  /// True only for explicit "yes" spellings; anything else is not a refund.
  bool get _refund =>
      const {'是', '1', 'true', 'Y', 'y', 'yes'}.contains(item.isRefund.trim());

  String get _title => item.merchantName.isNotEmpty
      ? item.merchantName
      : item.summary.isNotEmpty
      ? item.summary
      : '交易';

  void _details(BuildContext context) {
    showDetailSheet(
      context,
      title: _title,
      highlightLabel: '金额',
      highlight: item.amount,
      rows: [
        ('交易时间', item.date),
        ('商户', item.merchantName),
        ('摘要', item.summary),
        ('退款', _refund ? '是' : ''),
        ('流水号', item.journo),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final at = parseSchoolTimestamp(item.date);
    final time = at == null || (at.hour == 0 && at.minute == 0)
        ? ''
        : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final subtitle = joinMeta([
      time,
      if (item.merchantName.isNotEmpty) item.summary,
    ]);
    final amount = item.amount.trim();
    final income = amount.startsWith('+');
    return InkWell(
      onTap: () => _details(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  _refund ? Icons.undo_rounded : Icons.receipt_long_outlined,
                  size: 20,
                  color: scheme.primary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Wraps so the tag drops below a long name at large text.
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_refund)
                        TagChip(
                          label: '退款',
                          color: StatusColors.of(context).success,
                        ),
                    ],
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              amount,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: income
                    ? StatusColors.of(context).success
                    : scheme.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.state, required this.onRetry});

  final TransactionsState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final Widget child;
    if (state.failure != null && !state.isLoading) {
      child = InlineFailure(message: state.failure!.message, onRetry: onRetry);
    } else if (state.isLoading) {
      child = Semantics(
        label: '正在加载更多',
        child: const SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    } else if (state.hasMore) {
      child = TextButton(onPressed: onRetry, child: const Text('加载更多'));
    } else {
      child = Text('没有更多记录了', style: muted);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: AnimatedSwitcher(duration: AppMotion.medium, child: child),
      ),
    );
  }
}

class _TransactionsSkeleton extends StatelessWidget {
  const _TransactionsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '正在加载交易记录',
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Skeleton(width: 100, height: 14),
          SizedBox(height: AppSpacing.md),
          Skeleton(height: 64, radius: AppRadius.lg),
          SizedBox(height: AppSpacing.sm),
          Skeleton(height: 64, radius: AppRadius.lg),
          SizedBox(height: AppSpacing.sm),
          Skeleton(height: 64, radius: AppRadius.lg),
        ],
      ),
    );
  }
}
