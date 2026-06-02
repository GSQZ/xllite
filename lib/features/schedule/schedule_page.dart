import 'package:flutter/material.dart';

import '../../api/xjit_features.dart';
import '../common/async_content.dart';
import '../common/feature_data_page.dart';

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    return FeatureDataPage(
      title: '课表',
      feature: XjitFeature.schedule,
      emptyTitle: '暂时没有课表数据',
      validator: (data) => data['courses'] is List,
      builder: (context, data) {
        final courses = mapList(data['courses']);
        if (courses.isEmpty) {
          return const EmptyPanel(title: '当前学期没有课程');
        }
        return _ScheduleCalendar(
          term: textValue(data['term'], fallback: '当前学期'),
          courses: courses,
        );
      },
    );
  }
}

class _ScheduleCalendar extends StatefulWidget {
  const _ScheduleCalendar({required this.term, required this.courses});

  final String term;
  final List<Map<String, dynamic>> courses;

  @override
  State<_ScheduleCalendar> createState() => _ScheduleCalendarState();
}

class _ScheduleCalendarState extends State<_ScheduleCalendar> {
  late int _selectedDay;
  late int _selectedWeek;

  @override
  void initState() {
    super.initState();
    _selectedDay = _initialDayIndex();
    _selectedWeek = _initialTeachingWeek(widget.term);
  }

  static const _days = [
    _WeekDay('一', '星期一'),
    _WeekDay('二', '星期二'),
    _WeekDay('三', '星期三'),
    _WeekDay('四', '星期四'),
    _WeekDay('五', '星期五'),
    _WeekDay('六', '星期六'),
    _WeekDay('日', '星期日'),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedCourses = _coursesForDay(_selectedDay);
    final selectedDay = _days[_selectedDay];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _TermHeader(
          term: widget.term,
          totalCount: widget.courses.length,
          todayIndex: _initialDayIndex(),
          selectedWeek: _selectedWeek,
        ),
        const SizedBox(height: 14),
        _WeekCalibrator(
          selectedWeek: _selectedWeek,
          onChanged: (week) => setState(() => _selectedWeek = week),
        ),
        const SizedBox(height: 14),
        _WeekStrip(
          days: _days,
          selectedDay: _selectedDay,
          courseCountForDay: (index) => _coursesForDay(index).length,
          onSelected: (index) => setState(() => _selectedDay = index),
        ),
        const SizedBox(height: 18),
        _DayTitle(day: selectedDay.fullName, count: selectedCourses.length),
        const SizedBox(height: 12),
        if (selectedCourses.isEmpty)
          const EmptyPanel(
            title: '这天没有课程',
            subtitle: '可以切换上方星期查看其他课程。',
            icon: Icons.event_available_outlined,
          )
        else
          ...selectedCourses.map((course) => _TimelineCourse(course: course)),
      ],
    );
  }

  List<Map<String, dynamic>> _coursesForDay(int dayIndex) {
    final day = _days[dayIndex];
    final courses = widget.courses.where((course) {
      final courseDay = textValue(course['day'], fallback: '');
      final matchesDay = courseDay.contains(day.fullName) ||
          courseDay.contains('周${day.shortName}') ||
          courseDay.contains('星期${day.shortName}');
      return matchesDay && _courseMatchesWeek(course, _selectedWeek);
    }).toList();

    courses.sort((a, b) => _courseStart(a).compareTo(_courseStart(b)));
    return courses;
  }

  int _courseStart(Map<String, dynamic> course) {
    final sections = textValue(course['sections'], fallback: '');
    final sectionMatch = RegExp(r'\d+').firstMatch(sections);
    if (sectionMatch != null) {
      return int.tryParse(sectionMatch.group(0) ?? '') ?? 99;
    }

    final slot = textValue(course['slot'], fallback: '');
    const slotOrder = {
      '第一': 1,
      '第二': 3,
      '第三': 5,
      '第四': 7,
      '第五': 9,
      '第六': 11,
    };
    for (final entry in slotOrder.entries) {
      if (slot.contains(entry.key)) {
        return entry.value;
      }
    }
    return 99;
  }

  static int _initialDayIndex() {
    final weekday = DateTime.now().weekday;
    return weekday >= DateTime.monday && weekday <= DateTime.sunday
        ? weekday - 1
        : 0;
  }

  static int _initialTeachingWeek(String term) {
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

  static DateTime _firstMondayOfMonth(int year, int month) {
    var date = DateTime(year, month);
    while (date.weekday != DateTime.monday) {
      date = date.add(const Duration(days: 1));
    }
    return date;
  }

  bool _courseMatchesWeek(Map<String, dynamic> course, int week) {
    final weeks = textValue(course['weeks'], fallback: '');
    if (weeks.isEmpty || weeks == '-') {
      return true;
    }
    return _weekTextContainsWeek(weeks, week);
  }

  bool _weekTextContainsWeek(String text, int week) {
    final normalized = text
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
}

class _WeekDay {
  const _WeekDay(this.shortName, this.fullName);

  final String shortName;
  final String fullName;
}

class _TermHeader extends StatelessWidget {
  const _TermHeader({
    required this.term,
    required this.totalCount,
    required this.todayIndex,
    required this.selectedWeek,
  });

  final String term;
  final int totalCount;
  final int todayIndex;
  final int selectedWeek;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.calendar_view_week_outlined, color: colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    term,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '第 $selectedWeek 周 · 今天星期${_ScheduleCalendarState._days[todayIndex].shortName} · 共 $totalCount 条课程',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
}

class _WeekCalibrator extends StatelessWidget {
  const _WeekCalibrator({
    required this.selectedWeek,
    required this.onChanged,
  });

  final int selectedWeek;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            IconButton(
              onPressed: selectedWeek <= 1 ? null : () => onChanged(selectedWeek - 1),
              icon: const Icon(Icons.chevron_left),
              tooltip: '上一周',
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '第 $selectedWeek 周',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '按周次过滤课程',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: selectedWeek >= 25 ? null : () => onChanged(selectedWeek + 1),
              icon: const Icon(Icons.chevron_right),
              tooltip: '下一周',
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.days,
    required this.selectedDay,
    required this.courseCountForDay,
    required this.onSelected,
  });

  final List<_WeekDay> days;
  final int selectedDay;
  final int Function(int index) courseCountForDay;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: List.generate(days.length, (index) {
            final day = days[index];
            final isSelected = index == selectedDay;
            final count = courseCountForDay(index);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _WeekDayButton(
                  label: day.shortName,
                  count: count,
                  selected: isSelected,
                  onTap: () => onSelected(index),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _WeekDayButton extends StatelessWidget {
  const _WeekDayButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.onPrimary : colors.onSurface;
    final muted = selected ? colors.onPrimary.withValues(alpha: 0.78) : colors.outline;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 66,
        decoration: BoxDecoration(
          color: selected ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              count == 0 ? '空' : '$count节',
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayTitle extends StatelessWidget {
  const _DayTitle({required this.day, required this.count});

  final String day;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            day,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFEFFAF5),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              '$count 门课',
              style: const TextStyle(
                color: Color(0xFF047857),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineCourse extends StatelessWidget {
  const _TimelineCourse({required this.course});

  final Map<String, dynamic> course;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sections = textValue(course['sections'], fallback: textValue(course['slot']));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    child: Text(
                      sections,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.onSecondaryContainer,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 2,
                  height: 72,
                  margin: const EdgeInsets.only(top: 8),
                  color: const Color(0xFFE5E7EB),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      textValue(course['title'], fallback: '未命名课程'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 10),
                    _CourseMeta(
                      icon: Icons.person_outline,
                      text: textValue(course['teacher'], fallback: '教师未标注'),
                    ),
                    const SizedBox(height: 6),
                    _CourseMeta(
                      icon: Icons.place_outlined,
                      text: textValue(course['location'], fallback: '地点未标注'),
                    ),
                    const SizedBox(height: 6),
                    _CourseMeta(
                      icon: Icons.date_range_outlined,
                      text: textValue(course['weeks'], fallback: '周次未标注'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseMeta extends StatelessWidget {
  const _CourseMeta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
