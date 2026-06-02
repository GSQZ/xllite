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
  int? _selectedDay;
  int? _selectedWeek;
  late final DateTime _termStartDate;

  int get _currentDay {
    return _selectedDay ??= _initialDayIndex();
  }

  int get _currentWeek {
    return _selectedWeek ??= _initialTeachingWeek(widget.term);
  }

  @override
  void initState() {
    super.initState();
    _selectedDay = _initialDayIndex();
    _selectedWeek = _initialTeachingWeek(widget.term);
    _termStartDate = _termStartFor(widget.term);
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
    final selectedCourses = _coursesForDay(_currentDay);
    final selectedDay = _days[_currentDay];
    final selectedDate = _dateFor(_currentWeek, _currentDay);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
      children: [
        _CalendarHeader(
          term: widget.term,
          selectedWeek: _currentWeek,
          onPreviousWeek: _currentWeek <= 1
              ? null
              : () => setState(() => _selectedWeek = _currentWeek - 1),
          onNextWeek: _currentWeek >= 25
              ? null
              : () => setState(() => _selectedWeek = _currentWeek + 1),
          onToday: () => setState(() {
            _selectedWeek = _initialTeachingWeek(widget.term);
            _selectedDay = _initialDayIndex();
          }),
        ),
        const SizedBox(height: 12),
        _WeekStrip(
          days: _days,
          selectedDay: _currentDay,
          dateForDay: (index) => _dateFor(_currentWeek, index),
          courseCountForDay: (index) => _coursesForDay(index).length,
          onSelected: (index) => setState(() => _selectedDay = index),
        ),
        const SizedBox(height: 22),
        _DayTitle(
          day: selectedDay.fullName,
          date: selectedDate,
          count: selectedCourses.length,
        ),
        const SizedBox(height: 14),
        if (selectedCourses.isEmpty)
          const EmptyPanel(
            title: '这天没有课程',
            subtitle: '可以切换上方星期查看其他课程。',
            icon: Icons.event_available_outlined,
          )
        else
          ...selectedCourses.map((course) {
            return _TimelineCourse(course: _ScheduleCourse.fromMap(course));
          }),
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
      return matchesDay && _courseMatchesWeek(course, _currentWeek);
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

  static DateTime _termStartFor(String term) {
    final match = RegExp(r'(\d{4})-(\d{4})-(\d)').firstMatch(term);
    if (match == null) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: _initialDayIndex()));
    }

    final firstYear = int.tryParse(match.group(1) ?? '');
    final secondYear = int.tryParse(match.group(2) ?? '');
    final termIndex = int.tryParse(match.group(3) ?? '');
    if (firstYear == null || secondYear == null || termIndex == null) {
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: _initialDayIndex()));
    }

    return termIndex == 1
        ? _firstMondayOfMonth(firstYear, DateTime.september)
        : _firstMondayOfMonth(secondYear, DateTime.march);
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

  DateTime _dateFor(int week, int dayIndex) {
    return _termStartDate.add(Duration(days: (week - 1) * 7 + dayIndex));
  }
}

class _WeekDay {
  const _WeekDay(this.shortName, this.fullName);

  final String shortName;
  final String fullName;
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.term,
    required this.selectedWeek,
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.onToday,
  });

  final String term;
  final int selectedWeek;
  final VoidCallback? onPreviousWeek;
  final VoidCallback? onNextWeek;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '第 $selectedWeek 周',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                term,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onPreviousWeek,
          icon: const Icon(Icons.chevron_left),
          tooltip: '上一周',
        ),
        IconButton(
          onPressed: onToday,
          icon: const Icon(Icons.today_outlined),
          tooltip: '回到今天',
        ),
        IconButton(
          onPressed: onNextWeek,
          icon: const Icon(Icons.chevron_right),
          tooltip: '下一周',
        ),
      ],
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.days,
    required this.selectedDay,
    required this.dateForDay,
    required this.courseCountForDay,
    required this.onSelected,
  });

  final List<_WeekDay> days;
  final int selectedDay;
  final DateTime Function(int index) dateForDay;
  final int Function(int index) courseCountForDay;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: List.generate(days.length, (index) {
            final date = dateForDay(index);
            return Expanded(
              child: _WeekDayButton(
                label: days[index].shortName,
                date: date,
                count: courseCountForDay(index),
                selected: index == selectedDay,
                isToday: _isSameDate(date, DateTime.now()),
                onTap: () => onSelected(index),
              ),
            );
          }),
        ),
      ),
    );
  }

  bool _isSameDate(DateTime left, DateTime right) {
    return left.year == right.year && left.month == right.month && left.day == right.day;
  }
}

class _WeekDayButton extends StatelessWidget {
  const _WeekDayButton({
    required this.label,
    required this.date,
    required this.count,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final int count;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = selected ? colors.onPrimary : colors.onSurfaceVariant;
    final dateColor = selected ? colors.onPrimary : colors.onSurface;
    final dotColor = selected
        ? colors.onPrimary
        : count > 0
            ? colors.primary
            : colors.outlineVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: SizedBox(
        height: 74,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? colors.primary : Colors.transparent,
                shape: BoxShape.circle,
                border: isToday && !selected
                    ? Border.all(color: colors.primary, width: 1.2)
                    : null,
              ),
              child: SizedBox(
                width: 34,
                height: 34,
                child: Center(
                  child: Text(
                    '${date.day}',
                    style: TextStyle(
                      color: dateColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Container(
              width: count > 0 ? 5 : 3,
              height: count > 0 ? 5 : 3,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayTitle extends StatelessWidget {
  const _DayTitle({
    required this.day,
    required this.date,
    required this.count,
  });

  final String day;
  final DateTime date;
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
        Text(
          '${date.month}月${date.day}日 · $count 门课',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _ScheduleCourse {
  const _ScheduleCourse({
    required this.title,
    required this.teacher,
    required this.location,
    required this.weeks,
    required this.startMinutes,
    required this.endMinutes,
  });

  final String title;
  final String teacher;
  final String location;
  final String weeks;
  final int startMinutes;
  final int endMinutes;

  String get startText => _formatMinutes(startMinutes);
  String get endText => _formatMinutes(endMinutes);

  static _ScheduleCourse fromMap(Map<String, dynamic> course) {
    final sections = textValue(course['sections'], fallback: textValue(course['slot']));
    final range = _timeRangeForSections(sections);
    return _ScheduleCourse(
      title: textValue(course['title'], fallback: '未命名课程'),
      teacher: textValue(course['teacher'], fallback: '教师未标注'),
      location: textValue(course['location'], fallback: '地点未标注'),
      weeks: textValue(course['weeks'], fallback: '周次未标注'),
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
    return (_sectionStart(startSection), _sectionEnd(endSection));
  }

  static int _sectionStart(int section) {
    const starts = {
      1: 10 * 60,
      2: 10 * 60 + 55,
      3: 12 * 60,
      4: 12 * 60 + 55,
      5: 16 * 60,
      6: 16 * 60 + 55,
      7: 18 * 60,
      8: 18 * 60 + 55,
      9: 20 * 60 + 30,
      10: 21 * 60 + 25,
    };
    return starts[section] ?? 23 * 60 + 59;
  }

  static int _sectionEnd(int section) {
    const ends = {
      1: 10 * 60 + 45,
      2: 11 * 60 + 40,
      3: 12 * 60 + 45,
      4: 13 * 60 + 40,
      5: 16 * 60 + 45,
      6: 17 * 60 + 40,
      7: 18 * 60 + 45,
      8: 19 * 60 + 40,
      9: 21 * 60 + 15,
      10: 22 * 60 + 10,
    };
    return ends[section] ?? 23 * 60 + 59;
  }
}

class _TimelineCourse extends StatelessWidget {
  const _TimelineCourse({required this.course});

  final _ScheduleCourse course;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  course.startText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  course.endText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 3,
                          height: 22,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            course.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.74),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.place_outlined,
                              size: 16,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                course.location,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      height: 1.25,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${course.teacher} · ${course.weeks}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
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
