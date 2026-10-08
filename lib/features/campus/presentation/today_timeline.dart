import 'package:flutter/material.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../../shared/theme/app_theme.dart';
import 'campus_format.dart';
import 'section_parts.dart';

/// Whether today's list has anything trustworthy to show.
bool hasTimeline(DaySchedule? day) =>
    day != null &&
    const {
      DayScheduleStatus.incomplete,
      DayScheduleStatus.upcoming,
      DayScheduleStatus.inClass,
      DayScheduleStatus.finished,
    }.contains(day.status) &&
    (day.courses.isNotEmpty || day.unresolved.isNotEmpty);

/// Today's classes as a vertical timeline. Past classes dim, the current
/// one is highlighted; courses with unknown times are listed, not dropped.
class TodayTimeline extends StatelessWidget {
  const TodayTimeline({super.key, required this.day, required this.now});

  final DaySchedule day;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final rows = <_Row>[
      for (final course in day.courses)
        _Row(
          start: clockOf(course.startsAt),
          end: clockOf(course.endsAt),
          course: course.course,
          state: course.isOngoing(now)
              ? _RowState.current
              : course.endsAt.isAfter(now)
              ? _RowState.upcoming
              : _RowState.past,
        ),
      for (final course in day.unresolved)
        _Row(start: '待定', end: '', course: course, state: _RowState.unknown),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: '今日课程',
          trailing: day.unresolved.isEmpty
              ? '共 ${day.courses.length} 节'
              : '已识别 ${day.courses.length} 节',
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < rows.length; i++)
          _RowFrame(isLast: i == rows.length - 1, child: rows[i]),
      ],
    );
  }
}

enum _RowState { past, current, upcoming, unknown }

class _RowFrame extends StatelessWidget {
  const _RowFrame({required this.isLast, required this.child});

  final bool isLast;
  final _Row child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = child.state == _RowState.current;
    return AnimatedOpacity(
      opacity: child.state == _RowState.past ? 0.5 : 1,
      duration: AppMotion.long,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 52, child: child.timeColumn(context)),
            SizedBox(
              width: 24,
              child: Column(
                children: [
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: AppMotion.medium,
                    width: current ? 12 : 8,
                    height: current ? 12 : 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: current ? scheme.primary : scheme.surface,
                      border: Border.all(
                        color: current ? scheme.primary : scheme.outline,
                        width: current ? 3 : 1.5,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      ),
                      boxShadow: current
                          ? [
                              BoxShadow(
                                color: scheme.primary.withValues(alpha: 0.3),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 1.5,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: scheme.outlineVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: isLast ? 0 : AppSpacing.lg + 2,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.start,
    required this.end,
    required this.course,
    required this.state,
  });

  final String start;
  final String end;
  final ScheduleCourse course;
  final _RowState state;

  Widget timeColumn(BuildContext context) {
    final theme = Theme.of(context);
    final tabular = const [FontFeature.tabularFigures()];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          start,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: tabular,
            color: state == _RowState.current
                ? theme.colorScheme.primary
                : null,
          ),
        ),
        if (end.isNotEmpty)
          Text(
            end,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: tabular,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = joinMeta([
      course.location,
      sectionsText(course.sections),
      if (state == _RowState.unknown) weeksText(course.weeks),
      course.teacher,
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                course.title,
                style: theme.textTheme.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (state == _RowState.current)
              _Tag(label: '进行中', color: scheme.primary),
            if (state == _RowState.unknown)
              _Tag(label: '时间待定', color: StatusColors.of(context).warning),
          ],
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            meta,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsetsDirectional.only(start: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
