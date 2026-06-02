import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/xjit_api_client.dart';
import '../../api/xjit_features.dart';
import '../../auth/auth_controller.dart';
import '../card/card_page.dart';
import '../common/async_content.dart';
import '../common/feature_data_page.dart';
import '../electricity/electricity_page.dart';
import '../exams/exams_page.dart';
import '../grades/grades_page.dart';
import '../schedule/schedule_page.dart';
import '../settings/settings_page.dart';

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
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: [
                _HomeHeader(name: name, subtitle: major, online: data.health),
                const SizedBox(height: 26),
                const _FeatureList(),
                const SizedBox(height: 28),
                Text(
                  '民间开发版本，不代表学校官方应用。账号凭据只保存在本机。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
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

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '新理Lite',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            '$name · $subtitle',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: online ? const Color(0xFF10B981) : const Color(0xFFF97316),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                online ? '服务在线' : '服务异常',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  const _FeatureList();

  @override
  Widget build(BuildContext context) {
    final items = [
      _FeatureEntry(
        Icons.calendar_month_outlined,
        '课表',
        '按周查看课程',
        onTap: () => _open(context, const SchedulePage()),
      ),
      _FeatureEntry(
        Icons.event_note_outlined,
        '考试',
        '考试时间、地点、座位',
        onTap: () => _open(context, const ExamsPage()),
      ),
      _FeatureEntry(
        Icons.credit_card_outlined,
        '校园卡',
        '余额和最近流水',
        onTap: () => _open(context, const CardPage()),
      ),
      _FeatureEntry(
        Icons.bolt_outlined,
        '电费',
        '查询宿舍剩余电量',
        onTap: () => _open(context, const ElectricityPage()),
      ),
      _FeatureEntry(
        Icons.school_outlined,
        '成绩',
        '学分、绩点、课程成绩',
        onTap: () => _open(context, const GradesPage()),
      ),
      _FeatureEntry(
        Icons.person_outline,
        '我的',
        '账号和说明',
        onTap: () => _open(context, const SettingsPage()),
      ),
    ];

    return Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          items[index],
          if (index != items.length - 1) const ThinDivider(),
        ],
      ],
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _FeatureEntry extends StatelessWidget {
  const _FeatureEntry(this.icon, this.title, this.subtitle, {required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 22, color: colors.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }
}
