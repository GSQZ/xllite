import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../common/async_content.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).when(
          data: (value) => value,
          error: (error, stackTrace) => null,
          loading: () => null,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        children: [
          InfoCard(
            icon: Icons.account_circle_outlined,
            title: session?.username ?? '未登录',
            subtitle: 'CAS 学号',
          ),
          const ThinDivider(),
          const InfoCard(
            icon: Icons.privacy_tip_outlined,
            title: '隐私说明',
            subtitle: '账号密码只保存在本机安全存储，不会写入普通缓存和日志。',
          ),
          const ThinDivider(),
          const InfoCard(
            icon: Icons.info_outline,
            title: '关于新理Lite',
            subtitle: '新疆理工学院校园服务民间版，不代表学校官方应用。',
          ),
          const SizedBox(height: 26),
          OutlinedButton.icon(
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('退出登录'),
          ),
        ],
      ),
    );
  }
}
