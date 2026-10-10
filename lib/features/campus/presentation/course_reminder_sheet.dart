import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/frosted.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/top_sheet.dart';
import '../application/campus_controller.dart';
import '../application/course_activity_controller.dart';
import '../domain/schedule_planner.dart';
import 'accent_panel.dart';
import 'section_parts.dart';

Future<void> showCourseReminderSheet(
  BuildContext context, {
  required CampusController campus,
}) => showTopSheet<void>(
  context,
  barrierLabel: '关闭课前提醒设置',
  builder: (_) => CourseReminderSheet(campus: campus),
);

class CourseReminderSheet extends StatefulWidget {
  const CourseReminderSheet({super.key, required this.campus});
  final CampusController campus;

  @override
  State<CourseReminderSheet> createState() => _CourseReminderSheetState();
}

class _CourseReminderSheetState extends State<CourseReminderSheet> {
  CourseActivityController get controller => widget.campus.courseActivities;
  late final _listenable = Listenable.merge([
    controller,
    widget.campus.home.schedule,
  ]);
  bool _refreshing = false;
  bool get _busy => controller.busy || _refreshing;

  @override
  void initState() {
    super.initState();
    controller.refresh();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() => _refreshing = true);
    try {
      await widget.campus.home.load(refresh: true);
      await controller.refresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _setIsland(bool value) async {
    HapticFeedback.selectionClick();
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('开启灵动岛？'),
          content: const Text(
            '课前显示课程和倒计时。\n\n'
            'App 关闭或挂起后，提醒可能继续保留；重新打开 App 或手动移除即可收起。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开启'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await controller.configure(island: value);
  }

  Future<void> _showDetails() => showTopSheet<void>(
    context,
    barrierLabel: '关闭提醒说明',
    builder: (_) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _ReminderDetails(controller: controller),
    ),
  );

  /// Only the most actionable problem occupies the main sheet. Routine
  /// scheduling detail belongs in the secondary explanation, not four banners.
  Widget? _notice() {
    if (controller.error != null) {
      return _ReminderNotice(
        message: controller.error!,
        action: '重试',
        onAction: _busy ? null : controller.refresh,
        isError: true,
      );
    }
    if (!controller.enabled) return null;
    if (controller.notificationPermission == 'denied') {
      return _ReminderNotice(
        message: '通知未开启',
        action: '去设置',
        actionKey: const Key('reminders.settings'),
        onAction: controller.openSettings,
      );
    }
    if (controller.liveActivities && !controller.activitiesAllowed) {
      return _ReminderNotice(
        message: '实时活动未开启',
        action: '去设置',
        actionKey: const Key('reminders.settings'),
        onAction: controller.openSettings,
      );
    }
    if (widget.campus.home.schedule.state.failure != null) {
      return _ReminderNotice(
        message: '课表更新失败，已保留原提醒',
        action: '重试',
        onAction: _busy ? null : _refresh,
      );
    }
    if (!controller.hasCalendar) {
      return _ReminderNotice(
        message: '课表时间待同步',
        action: '同步',
        onAction: _busy ? null : _refresh,
      );
    }
    if (controller.schedulingWarning != null) {
      return _ReminderNotice(
        message: controller.schedulingWarning!,
        action: '重试',
        onAction: _busy ? null : controller.refresh,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _listenable,
    builder: (context, _) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final notice = _notice();
      final status = _busy
          ? '正在同步…'
          : controller.scheduledCount > 0
          ? '已安排 ${controller.scheduledCount} 次提醒'
          : controller.hasCalendar
          ? '暂无已安排提醒'
          : '等待课表同步';
      return AnimatedSize(
        key: const Key('reminders.sheetHeight'),
        duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.long,
        curve: AppMotion.emphasized,
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHeader(title: '课前提醒'),
              const SizedBox(height: AppSpacing.sm),
              AccentPanel(
                child: SwitchListTile.adaptive(
                  key: const Key('reminders.enabled'),
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: scheme.onPrimary,
                  activeTrackColor: scheme.onPrimary.withValues(alpha: 0.3),
                  inactiveThumbColor: scheme.onPrimary.withValues(alpha: 0.65),
                  inactiveTrackColor: scheme.onPrimary.withValues(alpha: 0.12),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '提前提醒',
                        style: onAccent(
                          context,
                          theme.textTheme.bodyMedium,
                          0.85,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '15',
                              style:
                                  onAccent(
                                    context,
                                    theme.textTheme.displaySmall,
                                  )?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
                                  ),
                            ),
                            TextSpan(
                              text: ' 分钟',
                              style: onAccent(
                                context,
                                theme.textTheme.titleMedium,
                                0.9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  value: controller.enabled,
                  onChanged: !controller.ready || _busy
                      ? null
                      : (value) {
                          HapticFeedback.selectionClick();
                          controller.configure(reminders: value);
                        },
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FrostedCard(
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      key: const Key('reminders.island'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.xs,
                      ),
                      secondary: Icon(
                        Icons.sensors_rounded,
                        color: scheme.primary,
                      ),
                      title: Text('灵动岛', style: theme.textTheme.bodyLarge),
                      subtitle: Text(
                        controller.scheduledSupported
                            ? '课程与倒计时'
                            : '需要 iOS 26 或更新版本',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      value: controller.liveActivities,
                      onChanged:
                          !controller.enabled ||
                              !controller.scheduledSupported ||
                              _busy
                          ? null
                          : _setIsland,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: Divider(height: 1, color: glassEdge(context)),
                    ),
                    ListTile(
                      key: const Key('reminders.details'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      leading: Icon(
                        Icons.info_outline_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                      title: Text('提醒说明', style: theme.textTheme.bodyLarge),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _showDetails,
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: AppMotion.reduced(context)
                    ? Duration.zero
                    : AppMotion.medium,
                transitionBuilder: sequentialTransition,
                // Outgoing content fades inside the shrinking sheet, without
                // holding its old height or responding to taps/announcements.
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  clipBehavior: Clip.none,
                  children: [
                    for (final child in previous)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: TickerMode(enabled: false, child: child),
                          ),
                        ),
                      ),
                    ?current,
                  ],
                ),
                child: Column(
                  key: ValueKey(notice != null || controller.enabled || _busy),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (notice != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      notice,
                    ],
                    if (controller.enabled || _busy) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xs),
                        child: Row(
                          children: [
                            Expanded(
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  status,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              key: const Key('reminders.refresh'),
                              tooltip: '同步课表与提醒',
                              onPressed: _busy ? null : _refresh,
                              icon: _busy
                                  ? SizedBox.square(
                                      dimension: AppSpacing.lg,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        semanticsLabel: '正在同步',
                                      ),
                                    )
                                  : const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ReminderNotice extends StatelessWidget {
  const _ReminderNotice({
    required this.message,
    required this.action,
    required this.onAction,
    this.actionKey,
    this.isError = false,
  });
  final String message, action;
  final VoidCallback? onAction;
  final Key? actionKey;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = isError
        ? theme.colorScheme.error
        : StatusColors.of(context).warning;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(Icons.info_outline_rounded, size: 18, color: tint),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: tint),
            ),
          ),
          TextButton(key: actionKey, onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}

class _ReminderDetails extends StatelessWidget {
  const _ReminderDetails({required this.controller});
  final CourseActivityController controller;

  String _date(DateTime date) {
    final civil = campusNow(date);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${civil.month}月${civil.day}日 ${two(civil.hour)}:${two(civil.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(title: '提醒说明'),
          const SizedBox(height: AppSpacing.md),
          Text('跟随实际课表', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '课前 15 分钟提醒，点击即可进入课表。打开 App 时会补充未来 7 天的课程安排。',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('灵动岛', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '最近两次课程优先显示灵动岛，其余使用普通通知，同一节课不重复提醒。App 运行时会在开课 1 分钟后收起；App 关闭或挂起时可能继续保留，重新打开或手动移除即可清理。',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('保持课表最新', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '长期未打开、临时调课、专注模式或权限变化可能影响提醒，请以最新课表为准。',
            style: theme.textTheme.bodyMedium,
          ),
          if (controller.scheduledUntil != null ||
              controller.lastSyncedAt != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Divider(color: glassEdge(context)),
            if (controller.scheduledUntil != null)
              Text(
                '已安排至 ${_date(controller.scheduledUntil!)}',
                style: theme.textTheme.bodySmall,
              ),
            if (controller.lastSyncedAt != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                '安排更新于 ${_date(controller.lastSyncedAt!)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}
