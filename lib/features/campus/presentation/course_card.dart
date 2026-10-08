import 'package:flutter/material.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/motion.dart';
import 'accent_panel.dart';
import 'campus_format.dart';

/// The one emphasized card on the home screen: what matters about classes
/// right now. Renders every [DayScheduleStatus] honestly — it never claims
/// "no classes" or a countdown without a complete basis for it.
class CourseCard extends StatelessWidget {
  const CourseCard({
    super.key,
    required this.snapshot,
    required this.onRetry,
    required this.onOpenSchedule,
  });

  final HomeSnapshot snapshot;
  final VoidCallback onRetry;
  final VoidCallback onOpenSchedule;

  @override
  Widget build(BuildContext context) {
    final view = _resolve();
    return KeyedSubtree(
      key: const Key('home.courseCard'),
      child: AccentPanel(
        child: AnimatedSize(
          duration: AppMotion.medium,
          curve: AppMotion.emphasized,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: AppMotion.long,
            switchInCurve: AppMotion.curve,
            switchOutCurve: AppMotion.exit,
            transitionBuilder: fadeThroughTransition,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [...previous, ?current],
            ),
            child: KeyedSubtree(
              key: ValueKey(view.key),
              child: view.build(context),
            ),
          ),
        ),
      ),
    );
  }

  _CardView _resolve() {
    final day = snapshot.day;
    final schedule = snapshot.schedule;
    final now = snapshot.now;
    if (day == null) {
      final failure = schedule.failure;
      if (failure != null && !schedule.isLoading) {
        return _CardView(
          'error',
          (context) => _MessageView(
            icon: Icons.cloud_off_rounded,
            title: '课表加载失败',
            message: failure.message,
            actionLabel: '重试',
            onAction: onRetry,
          ),
        );
      }
      return _CardView('loading', (context) => const _LoadingView());
    }
    final count = snapshot.schedule.data?.courses.length ?? 0;
    switch (day.status) {
      case DayScheduleStatus.needsCalendar:
        return _CardView(
          'needsCalendar',
          (context) => _MessageView(
            icon: Icons.event_note_rounded,
            title: '暂未配置校历',
            message: count == 0
                ? '课表已同步，本学期暂无课程。'
                : '已同步本学期 $count 门课程。校历确认后，这里会显示下一节课与倒计时。',
            actionLabel: '查看课表',
            onAction: onOpenSchedule,
          ),
        );
      case DayScheduleStatus.outsideTerm:
        return _CardView(
          'outsideTerm',
          (context) => _MessageView(
            icon: Icons.beach_access_rounded,
            title: '当前不在教学周',
            message: '假期中或学期尚未开始，课表仍可在课表页查看。',
            actionLabel: '查看课表',
            onAction: onOpenSchedule,
          ),
        );
      case DayScheduleStatus.noClasses:
        return _CardView(
          'noClasses',
          (context) => _MessageView(
            icon: Icons.wb_sunny_rounded,
            title: '今天没有课',
            message: '第 ${day.week} 周 · 今日没有课程安排',
          ),
        );
      case DayScheduleStatus.finished:
        return _CardView(
          'finished',
          (context) => _MessageView(
            icon: Icons.nights_stay_rounded,
            title: '今天的课已全部结束',
            message: '今日共 ${day.courses.length} 节课',
          ),
        );
      case DayScheduleStatus.inClass:
        final current = day.current!;
        return _CardView(
          'class:${current.startsAt}',
          (context) => _CourseView(
            label: '正在上课',
            trailing: '还剩 ${durationText(current.endsAt.difference(now))}',
            occurrence: current,
            progress: _progress(current, now),
          ),
        );
      case DayScheduleStatus.upcoming:
        final next = day.next!;
        final wait = next.startsAt.difference(now);
        return _CardView(
          'next:${next.startsAt}',
          (context) => _CourseView(
            label: '下一节',
            trailing: wait > const Duration(hours: 3)
                ? '${clockOf(next.startsAt)} 开始'
                : '还有 ${durationText(wait)}',
            occurrence: next,
          ),
        );
      case DayScheduleStatus.incomplete:
        final current = day.current;
        final unresolved = day.unresolved.length;
        // An ongoing parsed class is a fact; "next" could be wrong while
        // other courses have unknown times, so it is never claimed here.
        if (current != null) {
          return _CardView(
            'class:${current.startsAt}',
            (context) => _CourseView(
              label: '正在上课',
              trailing: '还剩 ${durationText(current.endsAt.difference(now))}',
              occurrence: current,
              progress: _progress(current, now),
              footnote: '另有 $unresolved 门课程时间无法确定',
            ),
          );
        }
        return _CardView(
          'incomplete',
          (context) => _MessageView(
            icon: Icons.help_outline_rounded,
            title: '部分课程时间待确认',
            message:
                '今日已识别 ${day.courses.length} 节，另有 $unresolved 门课程无法确定时间，请以教务系统为准。',
          ),
        );
    }
  }

  static double _progress(CourseOccurrence course, DateTime now) {
    final total = course.endsAt.difference(course.startsAt).inSeconds;
    if (total <= 0) return 1;
    return (now.difference(course.startsAt).inSeconds / total).clamp(0.0, 1.0);
  }
}

class _CardView {
  const _CardView(this.key, this.build);
  final String key;
  final WidgetBuilder build;
}

TextStyle? _onCard(
  BuildContext context,
  TextStyle? style, [
  double alpha = 1,
]) => style?.copyWith(
  color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: alpha),
);

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: onPrimary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: onPrimary, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: _onCard(
              context,
              Theme.of(context).textTheme.labelMedium,
            )?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _CourseView extends StatelessWidget {
  const _CourseView({
    required this.label,
    required this.trailing,
    required this.occurrence,
    this.progress,
    this.footnote,
  });

  final String label;
  final String trailing;
  final CourseOccurrence occurrence;
  final double? progress;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimary = theme.colorScheme.onPrimary;
    final course = occurrence.course;
    final time =
        '${clockOf(occurrence.startsAt)}–${clockOf(occurrence.endsAt)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Pill(label: label),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                trailing,
                textAlign: TextAlign.end,
                style: _onCard(context, theme.textTheme.bodyMedium, 0.9)
                    ?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          course.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _onCard(
            context,
            theme.textTheme.titleLarge,
          )?.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.xs + 2,
          children: [
            _Meta(icon: Icons.schedule_rounded, text: time),
            if (course.location.isNotEmpty)
              _Meta(icon: Icons.place_outlined, text: course.location),
            if (course.sections.isNotEmpty)
              _Meta(
                icon: Icons.view_agenda_outlined,
                text: sectionsText(course.sections),
              ),
            if (course.teacher.isNotEmpty)
              _Meta(icon: Icons.person_outline_rounded, text: course.teacher),
          ],
        ),
        if (progress != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Semantics(
            label: '本节课已进行 ${(progress! * 100).round()}%',
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              // Glides between the per-minute clock updates.
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: progress),
                duration: AppMotion.reduced(context)
                    ? Duration.zero
                    : AppMotion.entrance,
                curve: AppMotion.emphasized,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  color: onPrimary,
                  backgroundColor: onPrimary.withValues(alpha: 0.22),
                ),
              ),
            ),
          ),
        ],
        if (footnote != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            footnote!,
            style: _onCard(context, theme.textTheme.bodySmall, 0.85),
          ),
        ],
      ],
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
            style: _onCard(
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

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.onPrimary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.md + 2),
                ),
                child: Icon(icon, color: scheme.onPrimary, size: 24),
              ),
            ),
            const SizedBox(width: AppSpacing.md + 2),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: _onCard(
                        context,
                        theme.textTheme.titleMedium,
                      )?.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      message,
                      style: _onCard(context, theme.textTheme.bodyMedium, 0.88),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: PressScale(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.onPrimary,
                  foregroundColor: scheme.primary,
                  minimumSize: const Size(0, AppSizes.touchTarget - 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg + 2,
                  ),
                  shape: const StadiumBorder(),
                  textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 15),
                ),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    final tint = Theme.of(
      context,
    ).colorScheme.onPrimary.withValues(alpha: 0.22);
    return Semantics(
      label: '正在加载今日课程',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(width: 84, height: 24, radius: 99, color: tint),
          const SizedBox(height: AppSpacing.lg),
          Skeleton(width: 180, height: 26, color: tint),
          const SizedBox(height: AppSpacing.md),
          Skeleton(width: 240, height: 16, color: tint),
        ],
      ),
    );
  }
}
