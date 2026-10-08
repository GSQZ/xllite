import 'package:flutter/material.dart';

import '../../../shared/theme/app_theme.dart';
import '../application/course_activity_controller.dart';

class CourseActivityTestRow extends StatelessWidget {
  const CourseActivityTestRow({super.key, required this.controller});
  final CourseActivityController controller;

  Future<void> _change(BuildContext context, bool value) async {
    if (value) {
      final start = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('测试课前灵动岛'),
          content: const Text(
            'iOS 26 及以上会在 3 秒后显示，旧系统会立即显示。'
            '测试模拟 1 分钟后上课，再过 1 分钟结束。\n\n'
            '可以切到桌面或锁屏查看。当前测试在 App 关闭后可能无法自动结束，'
            '请返回这里关闭开关。正式课前自动提醒尚未启用。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开始测试'),
            ),
          ],
        ),
      );
      if (start != true) return;
    }
    await controller.setTesting(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = controller.busy
        ? '正在处理…'
        : switch (controller.phase) {
            'pending' => '已预约，即将出现在灵动岛',
            'upcoming' => '测试中 · 模拟课前倒计时',
            'started' => '测试中 · 已模拟上课',
            _ => '预览课前提醒',
          };
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
            Icons.notifications_active_outlined,
            size: 22,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('灵动岛测试', style: theme.textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(
                  controller.error ?? status,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: controller.error != null
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Switch.adaptive(
            key: const Key('mine.courseActivityTest'),
            value: controller.testing,
            onChanged: controller.busy
                ? null
                : (value) => _change(context, value),
          ),
        ],
      ),
    );
  }
}
