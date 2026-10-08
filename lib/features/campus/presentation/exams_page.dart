import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/state_panel.dart';
import 'accent_panel.dart';
import 'campus_format.dart';
import 'detail_sheet.dart';
import 'feature_page.dart';
import 'section_parts.dart';
import 'signed_in_memo.dart';

/// Exam schedule: the next exam up front, then the rest in time order,
/// exams whose time could not be read (shown with the original text) and,
/// folded away, the ones already finished.
class ExamsPage extends StatefulWidget {
  const ExamsPage({super.key, required this.auth, required this.campus});

  final AuthController auth;
  final CampusController campus;

  @override
  State<ExamsPage> createState() => _ExamsPageState();
}

class _ExamsPageState extends State<ExamsPage> {
  late final Listenable _listenable = Listenable.merge([
    widget.auth,
    widget.campus.exams,
  ]);
  final _memo = SignedInMemo<ResourceState<List<Exam>>>();
  Timer? _clock;
  var _showPast = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.campus.loadExams();
    });
    // Countdowns move with the clock; no school request is made.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _refresh() => widget.campus.loadExams(refresh: true);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _listenable,
      builder: (context, _) {
        final state = _memo.read(
          signedIn: widget.auth.state.isAuthenticated,
          live: () => widget.campus.exams.state,
        );
        return FeaturePage(
          title: '考试安排',
          scrollKey: const Key('exams.scroll'),
          onRefresh: _refresh,
          children: _content(context, state),
        );
      },
    );
  }

  List<Widget> _content(BuildContext context, ResourceState<List<Exam>> state) {
    final exams = state.data;
    if (exams == null) {
      final failure = state.failure;
      if (failure != null && !state.isLoading) {
        return [
          const SizedBox(height: AppSpacing.xxl),
          StatePanel(
            icon: Icons.cloud_off_rounded,
            tone: PanelTone.error,
            title: '考试安排加载失败',
            message: failure.message,
            actions: [
              FilledButton(
                onPressed: () => widget.campus.loadExams(),
                child: const Text('重试'),
              ),
            ],
          ),
        ];
      }
      return const [_ExamsSkeleton()];
    }

    final now = DateTime.now();
    final upcoming = <ExamOccurrence>[];
    final past = <ExamOccurrence>[];
    final undated = <Exam>[];
    for (final exam in exams) {
      final o = ExamOccurrence.parse(exam);
      if (o.endsAt == null) {
        undated.add(exam);
      } else if (o.endsAt!.isAfter(now)) {
        upcoming.add(o);
      } else {
        past.add(o);
      }
    }
    upcoming.sort((a, b) => a.startsAt!.compareTo(b.startsAt!));
    past.sort((a, b) => b.startsAt!.compareTo(a.startsAt!));

    return [
      _NextPanel(next: upcoming.firstOrNull, now: now, total: upcoming.length),
      if (state.isStale) ...[
        const SizedBox(height: AppSpacing.md),
        StaleNote(text: '${updatedText(state.updatedAt, now)} · 刷新失败，下拉重试'),
      ],
      if (upcoming.length > 1) ...[
        const SizedBox(height: AppSpacing.xl),
        SectionHeader(title: '接下来', trailing: '${upcoming.length - 1} 场'),
        const SizedBox(height: AppSpacing.sm),
        RowGroup(
          children: [
            for (final o in upcoming.skip(1)) ExamRow(occurrence: o, now: now),
          ],
        ),
      ],
      if (undated.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xl),
        SectionHeader(title: '时间待定', trailing: '${undated.length} 场'),
        const SizedBox(height: AppSpacing.sm),
        RowGroup(
          children: [
            for (final e in undated)
              ExamRow(occurrence: ExamOccurrence(e, null, null), now: now),
          ],
        ),
      ],
      if (past.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.xl),
        Semantics(
          button: true,
          expanded: _showPast,
          child: InkWell(
            key: const Key('exams.past'),
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => setState(() => _showPast = !_showPast),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSizes.touchTarget,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已结束',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '${past.length} 场',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  AnimatedRotation(
                    turns: _showPast ? 0.5 : 0,
                    duration: AppMotion.medium,
                    curve: AppMotion.emphasized,
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: AppMotion.long,
          curve: AppMotion.emphasized,
          alignment: Alignment.topCenter,
          child: _showPast
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Opacity(
                    opacity: 0.7,
                    child: RowGroup(
                      children: [
                        for (final o in past)
                          ExamRow(occurrence: o, now: now, finished: true),
                      ],
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
      if (exams.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: AppSpacing.xl),
          child: StatePanel(
            icon: Icons.event_available_rounded,
            title: '暂无考试安排',
            message: '教务系统发布考试安排后会显示在这里。',
          ),
        ),
    ];
  }
}

/// Countdown wording for an exam that has not ended.
String examCountdown(ExamOccurrence o, DateTime now) {
  final starts = o.startsAt!;
  final ends = o.endsAt!;
  if (!now.isBefore(starts)) {
    return '进行中 · 还剩 ${durationText(ends.difference(now))}';
  }
  final wait = starts.difference(now);
  if (wait < const Duration(hours: 3)) return '还有 ${durationText(wait)}';
  final days = daysUntil(starts, now);
  if (days == 0) return '今天 ${clockOf(starts)} 开始';
  if (days == 1) return '明天 ${clockOf(starts)} 开始';
  return '还有 $days 天';
}

class _NextPanel extends StatelessWidget {
  const _NextPanel({
    required this.next,
    required this.now,
    required this.total,
  });

  final ExamOccurrence? next;
  final DateTime now;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final o = next;
    if (o == null) {
      return AccentPanel(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.onPrimary.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppRadius.md + 2),
              ),
              child: Icon(
                Icons.event_available_rounded,
                color: scheme.onPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.md + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '近期没有待考科目',
                    style: onAccent(
                      context,
                      theme.textTheme.titleMedium,
                    )?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '有新的考试安排时会显示在这里',
                    style: onAccent(context, theme.textTheme.bodySmall, 0.85),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final exam = o.exam;
    final civil = campusNow(o.startsAt!);
    return AccentPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scheme.onPrimary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  total > 1 ? '下一场 · 共 $total 场待考' : '下一场考试',
                  style: onAccent(
                    context,
                    theme.textTheme.labelMedium,
                  )?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            examCountdown(o, now),
            key: const Key('exams.countdown'),
            style: onAccent(
              context,
              theme.textTheme.bodyLarge,
              0.9,
            )?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            exam.courseName,
            style: onAccent(
              context,
              theme.textTheme.titleLarge,
            )?.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.xs + 2,
            children: [
              _Meta(
                icon: Icons.event_rounded,
                text:
                    '${civilDateText(civil)} ${clockOf(o.startsAt!)}–${clockOf(o.endsAt!)}',
              ),
              if (exam.examPlace.isNotEmpty)
                _Meta(icon: Icons.place_outlined, text: exam.examPlace),
              if (exam.seatNo.isNotEmpty)
                _Meta(
                  icon: Icons.event_seat_outlined,
                  text: '座位 ${exam.seatNo}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: onPrimary.withValues(alpha: 0.85)),
        const SizedBox(width: AppSpacing.xs),
        Flexible(
          child: Text(
            text,
            style: onAccent(
              context,
              Theme.of(context).textTheme.bodyMedium,
              0.92,
            ),
          ),
        ),
      ],
    );
  }
}

/// One exam with a date badge; taps open every field in a sheet.
class ExamRow extends StatelessWidget {
  const ExamRow({
    super.key,
    required this.occurrence,
    required this.now,
    this.finished = false,
  });

  final ExamOccurrence occurrence;
  final DateTime now;
  final bool finished;

  void _details(BuildContext context) {
    final exam = occurrence.exam;
    final s = occurrence.startsAt;
    final e = occurrence.endsAt;
    showDetailSheet(
      context,
      title: exam.courseName,
      highlightLabel: s == null ? '考试时间' : null,
      highlight: s == null
          ? (exam.examTime.isEmpty ? '时间未公布' : exam.examTime)
          : '${civilDateText(campusNow(s))} ${clockOf(s)}–${clockOf(e!)}',
      rows: [
        ('考试地点', exam.examPlace),
        ('座位号', exam.seatNo),
        ('考试场次', exam.examSession),
        ('校区', exam.campus),
        ('任课教师', exam.teacher),
        ('课程编号', exam.courseCode),
        if (s != null) ('原始时间', exam.examTime),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final exam = occurrence.exam;
    final starts = occurrence.startsAt;
    final ends = occurrence.endsAt;
    final days = starts == null || finished ? null : daysUntil(starts, now);
    final civil = starts == null ? null : campusNow(starts);
    final when = starts != null && ends != null
        ? '${civilDateText(civil!)} ${clockOf(starts)}–${clockOf(ends)}'
        : exam.examTime.isEmpty
        ? '考试时间未公布'
        : exam.examTime;
    final where = joinMeta([
      exam.examPlace,
      if (exam.seatNo.isNotEmpty) '座位 ${exam.seatNo}',
    ]);
    final soon = days != null && days <= 1;
    final accent = soon ? StatusColors.of(context).warning : scheme.primary;
    final badgeTint = civil == null || finished
        ? scheme.onSurfaceVariant
        : accent;

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
                constraints: const BoxConstraints(minWidth: 50, minHeight: 54),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: badgeTint.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md + 2),
                ),
                alignment: Alignment.center,
                child: civil == null
                    ? Text(
                        '待定',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${civil.month}月',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: badgeTint,
                            ),
                          ),
                          Text(
                            '${civil.day}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                              color: badgeTint,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.md + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exam.courseName,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    when,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (where.isNotEmpty)
                    Text(
                      where,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (days != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  relativeDays(days),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExamsSkeleton extends StatelessWidget {
  const _ExamsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '正在加载考试安排',
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Skeleton(height: 168, radius: AppRadius.xl),
          SizedBox(height: AppSpacing.xl),
          Skeleton(height: 74, radius: AppRadius.lg),
          SizedBox(height: AppSpacing.sm),
          Skeleton(height: 74, radius: AppRadius.lg),
        ],
      ),
    );
  }
}
