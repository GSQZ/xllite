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
  late int _selectedDay = _initialDayIndex();

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
      return courseDay.contains(day.fullName) ||
          courseDay.contains('周${day.shortName}') ||
          courseDay.contains('星期${day.shortName}');
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
  });

  final String term;
  final int totalCount;
  final int todayIndex;

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
                    '共 $totalCount 条课程 · 今天星期${_ScheduleCalendarState._days[todayIndex].shortName}',
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
