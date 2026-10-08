import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../ui/xl_theme.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            children: [
              InfoCard(
                icon: LucideIcons.userRound,
                title: session?.username ?? '未登录',
                subtitle: 'CAS 学号',
                trailing: TextButton.icon(
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).signOut(),
                  icon: Icon(LucideIcons.logOut, color: colors.error, size: 18),
                  label: Text('退出登录', style: TextStyle(color: colors.error)),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '还有一些重要的小事，正在路上。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
              Text(
                '${AppConfig.appName} ${AppConfig.appVersion}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: XLColors.inkTertiary,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
