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
    final results = await Future.wait([
      api.health(),
      api.run(
        XjitFeature.profile,
        username: session.username,
        password: session.password,
      ),
      api.run(
        XjitFeature.schedule,
        username: session.username,
        password: session.password,
      ),
    ]);
    return HomeSnapshot(
      health: results[0] as bool,
      profile: results[1] as Map<String, dynamic>,
      schedule: results[2] as Map<String, dynamic>,
    );
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

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _WelcomeHeader(name: name),
                const SizedBox(height: 16),
                _TodayCoursePanel(schedule: data.schedule),
                const SizedBox(height: 16),
                Text(
                  '常用功能',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                const _FeatureGrid(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class HomeSnapshot {
  const HomeSnapshot({
    required this.health,
    required this.profile,
    required this.schedule,
  });

  final bool health;
  final Map<String, dynamic> profile;
  final Map<String, dynamic> schedule;
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final greeting = _greetingFor(_shortName(name));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 42,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    greeting.subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _GreetingCopy _greetingFor(String name) {
    final hour = DateTime.now().hour;
    if (hour < 5) {
      return _GreetingCopy('$name同学，夜深了', '先休息，明天再继续。');
    }
    if (hour < 11) {
      return _GreetingCopy('上午好，$name同学', '从今天的课程开始。');
    }
    if (hour < 14) {
      return _GreetingCopy('中午好，$name同学', '看一眼下午安排。');
    }
    if (hour < 18) {
      return _GreetingCopy('下午好，$name同学', '今天也保持节奏。');
    }
    return _GreetingCopy('晚上好，$name同学', '复盘一下今天的事项。');
  }

  String _shortName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '同学') {
      return '同学';
    }
    return trimmed.characters.first;
  }
}

class _GreetingCopy {
  const _GreetingCopy(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

class _TodayCoursePanel extends StatelessWidget {
  const _TodayCoursePanel({required this.schedule});

  final Map<String, dynamic> schedule;

  @override
  Widget build(BuildContext context) {
    final courses = _todayCourses();
    final active = _activeCourse(courses);
    final next = _nextCourse(courses);

    if (courses.isEmpty) {
      return const InfoCard(
        icon: Icons.event_available_outlined,
        title: '今天没有课程',
        subtitle: '可以去课表查看其他日期安排。',
      );
    }

    if (active == null && next == null) {
      return const InfoCard(
        icon: Icons.done_all_outlined,
        title: '今天课程已结束',
        subtitle: '可以去课表查看明天安排。',
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              active == null ? '下一节课' : '正在上课',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            if (active != null) _CourseBrief(course: active, prominent: true),
            if (active != null && next != null) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 14),
              Text(
                '下一节',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              _CourseBrief(course: next, prominent: false),
            ],
            if (active == null && next != null)
              _CourseBrief(course: next, prominent: true),
          ],
        ),
      ),
    );
  }

  List<_HomeCourse> _todayCourses() {
    final rawCourses = mapList(schedule['courses']);
    final now = DateTime.now();
    final week = _initialTeachingWeek(textValue(schedule['term'], fallback: ''));
    final dayIndex = now.weekday - 1;
    if (dayIndex < 0 || dayIndex > 6) {
      return const [];
    }

    final courses = rawCourses
        .where((course) => _matchesDay(course, dayIndex))
        .where((course) => _matchesWeek(course, week))
        .map(_HomeCourse.fromMap)
        .toList();
    courses.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return courses;
  }

  _HomeCourse? _activeCourse(List<_HomeCourse> courses) {
    final minutes = _nowMinutes();
    for (final course in courses) {
      if (minutes >= course.startMinutes && minutes <= course.endMinutes) {
        return course;
      }
    }
    return null;
  }

  _HomeCourse? _nextCourse(List<_HomeCourse> courses) {
    final minutes = _nowMinutes();
    for (final course in courses) {
      if (course.startMinutes > minutes) {
        return course;
      }
    }
    return null;
  }

  int _nowMinutes() {
    final now = DateTime.now();
    return now.hour * 60 + now.minute;
  }

  bool _matchesDay(Map<String, dynamic> course, int dayIndex) {
    const days = [
      ('一', '星期一'),
      ('二', '星期二'),
      ('三', '星期三'),
      ('四', '星期四'),
      ('五', '星期五'),
      ('六', '星期六'),
      ('日', '星期日'),
    ];
    final day = days[dayIndex];
    final value = textValue(course['day'], fallback: '');
    return value.contains(day.$2) ||
        value.contains('周${day.$1}') ||
        value.contains('星期${day.$1}');
  }

  bool _matchesWeek(Map<String, dynamic> course, int week) {
    final weeks = textValue(course['weeks'], fallback: '');
    if (weeks.isEmpty || weeks == '-') {
      return true;
    }

    final normalized = weeks
        .replaceAll('－', '-')
        .replaceAll('—', '-')
        .replaceAll('~', '-')
        .replaceAll('～', '-')
        .replaceAll('至', '-')
        .replaceAll('到', '-');

    if ((normalized.contains('单') || normalized.toLowerCase().contains('odd')) &&
        week.isEven) {
      return false;
    }
    if ((normalized.contains('双') || normalized.toLowerCase().contains('even')) &&
        week.isOdd) {
      return false;
    }

    var withoutRanges = normalized;
    var hasNumbers = false;
    for (final match in RegExp(r'(\d+)\s*-\s*(\d+)').allMatches(normalized)) {
      hasNumbers = true;
      final start = int.tryParse(match.group(1) ?? '');
      final end = int.tryParse(match.group(2) ?? '');
      if (start != null && end != null && week >= start && week <= end) {
        return true;
      }
      withoutRanges = withoutRanges.replaceFirst(match.group(0) ?? '', ' ');
    }

    for (final match in RegExp(r'\d+').allMatches(withoutRanges)) {
      hasNumbers = true;
      if (int.tryParse(match.group(0) ?? '') == week) {
        return true;
      }
    }

    return !hasNumbers;
  }

  int _initialTeachingWeek(String term) {
    final now = DateTime.now();
    final match = RegExp(r'(\d{4})-(\d{4})-(\d)').firstMatch(term);
    if (match == null) {
      return 1;
    }

    final firstYear = int.tryParse(match.group(1) ?? '');
    final secondYear = int.tryParse(match.group(2) ?? '');
    final termIndex = int.tryParse(match.group(3) ?? '');
    if (firstYear == null || secondYear == null || termIndex == null) {
      return 1;
    }

    final start = termIndex == 1
        ? _firstMondayOfMonth(firstYear, DateTime.september)
        : _firstMondayOfMonth(secondYear, DateTime.march);
    final days = now.difference(start).inDays;
    if (days < 0) {
      return 1;
    }
    return (days ~/ 7 + 1).clamp(1, 25);
  }

  DateTime _firstMondayOfMonth(int year, int month) {
    var date = DateTime(year, month);
    while (date.weekday != DateTime.monday) {
      date = date.add(const Duration(days: 1));
    }
    return date;
  }
}

class _CourseBrief extends StatelessWidget {
  const _CourseBrief({required this.course, required this.prominent});

  final _HomeCourse course;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: prominent
                ? colors.primaryContainer.withValues(alpha: 0.7)
                : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            child: Text(
              course.sections,
              style: TextStyle(
                color: prominent ? colors.primary : colors.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                course.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 5),
              Text(
                '${course.timeText} · ${course.location}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              if (course.teacher != '-') ...[
                const SizedBox(height: 3),
                Text(
                  course.teacher,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HomeCourse {
  const _HomeCourse({
    required this.title,
    required this.teacher,
    required this.location,
    required this.sections,
    required this.startMinutes,
    required this.endMinutes,
  });

  final String title;
  final String teacher;
  final String location;
  final String sections;
  final int startMinutes;
  final int endMinutes;

  String get timeText {
    return '${_formatMinutes(startMinutes)}-${_formatMinutes(endMinutes)}';
  }

  static _HomeCourse fromMap(Map<String, dynamic> course) {
    final sections = textValue(course['sections'], fallback: textValue(course['slot']));
    final range = _timeRangeForSections(sections);
    return _HomeCourse(
      title: textValue(course['title'], fallback: '未命名课程'),
      teacher: textValue(course['teacher']),
      location: textValue(course['location']),
      sections: sections,
      startMinutes: range.$1,
      endMinutes: range.$2,
    );
  }

  static String _formatMinutes(int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static (int, int) _timeRangeForSections(String sections) {
    final numbers = RegExp(r'\d+')
        .allMatches(sections)
        .map((match) => int.tryParse(match.group(0) ?? ''))
        .whereType<int>()
        .toList();
    final startSection = numbers.isEmpty ? 1 : numbers.first;
    final endSection = numbers.isEmpty ? startSection : numbers.last;
    return (
      _sectionStart(startSection),
      _sectionEnd(endSection),
    );
  }

  static int _sectionStart(int section) {
    const starts = {
      1: 10 * 60,
      2: 10 * 60 + 55,
      3: 12 * 60,
      4: 12 * 60 + 55,
      5: 14 * 60 + 30,
      6: 15 * 60 + 25,
      7: 16 * 60 + 30,
      8: 17 * 60 + 25,
      9: 19 * 60 + 30,
      10: 20 * 60 + 25,
      11: 21 * 60 + 20,
      12: 22 * 60 + 15,
    };
    return starts[section] ?? 23 * 60 + 59;
  }

  static int _sectionEnd(int section) {
    const ends = {
      1: 10 * 60 + 45,
      2: 11 * 60 + 40,
      3: 12 * 60 + 45,
      4: 13 * 60 + 40,
      5: 15 * 60 + 15,
      6: 16 * 60 + 10,
      7: 17 * 60 + 15,
      8: 18 * 60 + 10,
      9: 20 * 60 + 15,
      10: 21 * 60 + 10,
      11: 22 * 60 + 5,
      12: 23 * 60,
    };
    return ends[section] ?? 23 * 60 + 59;
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  @override
  Widget build(BuildContext context) {
    final items = [
      _FeatureShortcut(
        Icons.calendar_month_outlined,
        '课表',
        '本周课程',
        onTap: () => _open(context, const SchedulePage()),
      ),
      _FeatureShortcut(
        Icons.event_note_outlined,
        '考试',
        '安排和座位',
        onTap: () => _open(context, const ExamsPage()),
      ),
      _FeatureShortcut(
        Icons.credit_card_outlined,
        '校园卡',
        '余额流水',
        onTap: () => _open(context, const CardPage()),
      ),
      _FeatureShortcut(
        Icons.bolt_outlined,
        '电费',
        '宿舍余电',
        onTap: () => _open(context, const ElectricityPage()),
      ),
      _FeatureShortcut(
        Icons.school_outlined,
        '成绩',
        '学分绩点',
        onTap: () => _open(context, const GradesPage()),
      ),
      _FeatureShortcut(
        Icons.person_outline,
        '我的',
        '账号设置',
        onTap: () => _open(context, const SettingsPage()),
      ),
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

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _FeatureShortcut extends StatelessWidget {
  const _FeatureShortcut(this.icon, this.title, this.subtitle, {this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
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
      ),
    );
  }
}
