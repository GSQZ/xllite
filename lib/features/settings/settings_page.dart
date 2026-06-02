import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../theme/app_theme_controller.dart';
import '../common/async_content.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final session = ref
        .watch(authControllerProvider)
        .when(
          data: (value) => value,
          error: (error, stackTrace) => null,
          loading: () => null,
        );
    final themeSettings = ref
        .watch(appThemeControllerProvider)
        .maybeWhen(
          data: (value) => value,
          orElse: () => AppThemeSettings.defaults,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InfoCard(
            icon: Icons.account_circle_outlined,
            title: session?.username ?? '未登录',
            subtitle: 'CAS 学号',
          ),
          const SizedBox(height: 10),
          _ThemeSettingsCard(
            settings: themeSettings,
            onModeChanged: (mode) {
              ref.read(appThemeControllerProvider.notifier).setMode(mode);
            },
            onColorChanged: (color) {
              ref.read(appThemeControllerProvider.notifier).setColor(color);
            },
          ),
          const SizedBox(height: 10),
          const InfoCard(
            icon: Icons.privacy_tip_outlined,
            title: '隐私说明',
            subtitle: '账号密码只保存在本机安全存储，不会写入普通缓存和日志。',
          ),
          const SizedBox(height: 10),
          const InfoCard(
            icon: Icons.info_outline,
            title: '关于新理Lite',
            subtitle: '新疆理工学院校园服务民间版，不代表学校官方应用。',
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
            label: Text('退出登录', style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );
  }
}

class _ThemeSettingsCard extends StatelessWidget {
  const _ThemeSettingsCard({
    required this.settings,
    required this.onModeChanged,
    required this.onColorChanged,
  });

  final AppThemeSettings settings;
  final ValueChanged<AppThemeModeChoice> onModeChanged;
  final ValueChanged<AppThemeColorChoice> onColorChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette_outlined, color: colors.primary),
                const SizedBox(width: 10),
                Text(
                  '外观',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '模式',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<AppThemeModeChoice>(
              showSelectedIcon: false,
              segments: AppThemeModeChoice.values.map((mode) {
                return ButtonSegment(value: mode, label: Text(mode.label));
              }).toList(),
              selected: {settings.mode},
              onSelectionChanged: (selected) => onModeChanged(selected.first),
            ),
            const SizedBox(height: 18),
            Text(
              '主题色',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: AppThemeColorChoice.values.map((choice) {
                return _ThemeColorSwatch(
                  choice: choice,
                  selected: settings.color == choice,
                  onTap: () => onColorChanged(choice),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeColorSwatch extends StatelessWidget {
  const _ThemeColorSwatch({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final AppThemeColorChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: choice.color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? colors.onSurface : Colors.transparent,
                  width: 2,
                ),
              ),
              child: SizedBox(
                width: 34,
                height: 34,
                child: selected
                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              choice.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected ? colors.onSurface : colors.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
