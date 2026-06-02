import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/xjit_api_client.dart';
import '../../api/xjit_features.dart';
import '../../auth/auth_controller.dart';
import '../common/async_content.dart';
import '../common/feature_data_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late Future<HomeSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<HomeSnapshot> _load() async {
    final session = ref.read(authControllerProvider).when(
          data: (value) => value,
          error: (error, stackTrace) => null,
          loading: () => null,
        );
    if (session == null) {
      throw const XjitApiException('请先登录');
    }
    final api = ref.read(xjitApiClientProvider);
    final health = await api.health();
    final profile = await api.run(
      XjitFeature.profile,
      username: session.username,
      password: session.password,
    );
    return HomeSnapshot(health: health, profile: profile);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    try {
      await _future;
    } catch (_) {
      // FutureBuilder owns the visible error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新理Lite')),
      body: FutureBuilder<HomeSnapshot>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingPanel(label: '正在准备校园数据');
          }
          if (snapshot.hasError) {
            return ErrorPanel(error: snapshot.error!, onRetry: _refresh);
          }

          final data = snapshot.data!;
          final name = textValue(data.profile['name'], fallback: '同学');
          final major = textValue(data.profile['major'], fallback: '新疆理工学院');

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _WelcomePanel(name: name, subtitle: major, online: data.health),
                const SizedBox(height: 16),
                Text(
                  '常用功能',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                const _FeatureGrid(),
                const SizedBox(height: 16),
                const InfoCard(
                  icon: Icons.info_outline,
                  title: '民间开发版本',
                  subtitle: '新理Lite 不代表新疆理工学院官方应用，账号凭据只保存在本机。',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class HomeSnapshot {
  const HomeSnapshot({required this.health, required this.profile});

  final bool health;
  final Map<String, dynamic> profile;
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({
    required this.name,
    required this.subtitle,
    required this.online,
  });

  final String name;
  final String subtitle;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$name，今天看点什么',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 14),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: online ? const Color(0xFFEFFAF5) : const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Text(
                        online ? '接口在线' : '接口异常',
                        style: TextStyle(
                          color: online ? const Color(0xFF047857) : const Color(0xFFC2410C),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Icon(Icons.dashboard_outlined, color: colors.primary, size: 42),
          ],
        ),
      ),
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  @override
  Widget build(BuildContext context) {
    const items = [
      _FeatureShortcut(Icons.calendar_month_outlined, '课表', '本周课程'),
      _FeatureShortcut(Icons.event_note_outlined, '考试', '安排和座位'),
      _FeatureShortcut(Icons.credit_card_outlined, '校园卡', '余额流水'),
      _FeatureShortcut(Icons.bolt_outlined, '电费', '宿舍余电'),
      _FeatureShortcut(Icons.school_outlined, '成绩', '学分绩点'),
      _FeatureShortcut(Icons.person_outline, '信息', '个人资料'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.75,
      ),
      itemBuilder: (context, index) => items[index],
    );
  }
}

class _FeatureShortcut extends StatelessWidget {
  const _FeatureShortcut(this.icon, this.title, this.subtitle);

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
