import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
  _ScheduleViewMode _viewMode = _ScheduleViewMode.agenda;
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
    final weeklyCourses = _coursesForWeek();

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
        const SizedBox(height: 16),
        _ScheduleModeSwitch(
          value: _viewMode,
          onChanged: (value) => setState(() => _viewMode = value),
        ),
        const SizedBox(height: 18),
        if (_viewMode == _ScheduleViewMode.week) ...[
          _WeekCalendarGrid(
            days: _days,
            selectedDay: _currentDay,
            dateForDay: (index) => _dateFor(_currentWeek, index),
            coursesForSlot: (dayIndex, slot) {
              return weeklyCourses
                  .where((course) {
                    return course.dayIndex == dayIndex &&
                        course.course.startMinutes == slot.startMinutes;
                  })
                  .map((course) => course.course)
                  .toList();
            },
            onDaySelected: (index) => setState(() {
              _selectedDay = index;
              _viewMode = _ScheduleViewMode.agenda;
            }),
          ),
        ] else ...[
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
              icon: LucideIcons.calendarCheck,
            )
          else
            ...selectedCourses.map((course) {
              return _AgendaCourseCard(course: _ScheduleCourse.fromMap(course));
            }),
        ],
      ],
    );
  }

  List<Map<String, dynamic>> _coursesForDay(int dayIndex) {
    final day = _days[dayIndex];
    final courses = widget.courses.where((course) {
      final courseDay = textValue(course['day'], fallback: '');
      final matchesDay =
          courseDay.contains(day.fullName) ||
          courseDay.contains('周${day.shortName}') ||
          courseDay.contains('星期${day.shortName}');
      return matchesDay && _courseMatchesWeek(course, _currentWeek);
    }).toList();

    courses.sort((a, b) => _courseStart(a).compareTo(_courseStart(b)));
    return courses;
  }

  List<_WeekCourse> _coursesForWeek() {
    final courses = <_WeekCourse>[];
    for (var dayIndex = 0; dayIndex < _days.length; dayIndex += 1) {
      for (final course in _coursesForDay(dayIndex)) {
        courses.add(
          _WeekCourse(
            dayIndex: dayIndex,
            course: _ScheduleCourse.fromMap(course),
          ),
        );
      }
    }
    courses.sort((a, b) {
      final dayCompare = a.dayIndex.compareTo(b.dayIndex);
      if (dayCompare != 0) {
        return dayCompare;
      }
      return a.course.startMinutes.compareTo(b.course.startMinutes);
    });
    return courses;
  }

  int _courseStart(Map<String, dynamic> course) {
    final sections = textValue(course['sections'], fallback: '');
    final sectionMatch = RegExp(r'\d+').firstMatch(sections);
    if (sectionMatch != null) {
      return int.tryParse(sectionMatch.group(0) ?? '') ?? 99;
    }

    final slot = textValue(course['slot'], fallback: '');
    const slotOrder = {'第一': 1, '第二': 3, '第三': 5, '第四': 7, '第五': 9, '第六': 11};
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
      return DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: _initialDayIndex()));
    }

    final firstYear = int.tryParse(match.group(1) ?? '');
    final secondYear = int.tryParse(match.group(2) ?? '');
    final termIndex = int.tryParse(match.group(3) ?? '');
    if (firstYear == null || secondYear == null || termIndex == null) {
      final now = DateTime.now();
      return DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: _initialDayIndex()));
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

    if ((normalized.contains('单') ||
            normalized.toLowerCase().contains('odd')) &&
        week.isEven) {
      return false;
    }
    if ((normalized.contains('双') ||
            normalized.toLowerCase().contains('even')) &&
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

enum _ScheduleViewMode { agenda, week }

class _WeekCourse {
  const _WeekCourse({required this.dayIndex, required this.course});

  final int dayIndex;
  final _ScheduleCourse course;
}

class _WeekDay {
  const _WeekDay(this.shortName, this.fullName);

  final String shortName;
  final String fullName;
}

class _WeekSlot {
  const _WeekSlot(this.label, this.time, this.startMinutes);

  final String label;
  final String time;
  final int startMinutes;
}

const _weekSlots = [
  _WeekSlot('1-2', '10:00', 10 * 60),
  _WeekSlot('3-4', '12:00', 12 * 60),
  _WeekSlot('5-6', '16:00', 16 * 60),
  _WeekSlot('7-8', '18:00', 18 * 60),
  _WeekSlot('9-10', '20:30', 20 * 60 + 30),
];

Color _courseAccent(String value) {
  const colors = [
    Color(0xFF2563EB),
    Color(0xFF059669),
    Color(0xFFD97706),
    Color(0xFF7C3AED),
    Color(0xFFDC2626),
  ];
  return colors[value.hashCode.abs() % colors.length];
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
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onPreviousWeek,
          icon: const Icon(LucideIcons.chevronLeft),
          tooltip: '上一周',
        ),
        IconButton(
          onPressed: onToday,
          icon: const Icon(LucideIcons.calendarDays),
          tooltip: '回到今天',
        ),
        IconButton(
          onPressed: onNextWeek,
          icon: const Icon(LucideIcons.chevronRight),
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
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
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
  const _DayTitle({required this.day, required this.date, required this.count});

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
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
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

class _ScheduleModeSwitch extends StatelessWidget {
  const _ScheduleModeSwitch({required this.value, required this.onChanged});

  final _ScheduleViewMode value;
  final ValueChanged<_ScheduleViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: [
            _ScheduleModeButton(
              label: '日程',
              selected: value == _ScheduleViewMode.agenda,
              onTap: () => onChanged(_ScheduleViewMode.agenda),
            ),
            _ScheduleModeButton(
              label: '周视图',
              selected: value == _ScheduleViewMode.week,
              onTap: () => onChanged(_ScheduleViewMode.week),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleModeButton extends StatelessWidget {
  const _ScheduleModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? colors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: colors.shadow.withValues(alpha: 0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected ? colors.onSurface : colors.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekCalendarGrid extends StatelessWidget {
  const _WeekCalendarGrid({
    required this.days,
    required this.selectedDay,
    required this.dateForDay,
    required this.coursesForSlot,
    required this.onDaySelected,
  });

  final List<_WeekDay> days;
  final int selectedDay;
  final DateTime Function(int index) dateForDay;
  final List<_ScheduleCourse> Function(int dayIndex, _WeekSlot slot)
  coursesForSlot;
  final ValueChanged<int> onDaySelected;

  static const _headerHeight = 58.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final gridHeight = (screenHeight - 252).clamp(620.0, 760.0);
    final slotHeight = (gridHeight - _headerHeight) / _weekSlots.length;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final dayColumnWidth = constraints.maxWidth / days.length;

            return SizedBox(
              height: gridHeight,
              width: constraints.maxWidth,
              child: Column(
                children: [
                  _WeekCalendarHeaderRow(
                    days: days,
                    selectedDay: selectedDay,
                    dateForDay: dateForDay,
                    dayColumnWidth: dayColumnWidth,
                    onDaySelected: onDaySelected,
                  ),
                  for (final slot in _weekSlots)
                    _WeekCalendarSlotRow(
                      slot: slot,
                      days: days,
                      dayColumnWidth: dayColumnWidth,
                      slotHeight: slotHeight,
                      coursesForSlot: coursesForSlot,
                      onDaySelected: onDaySelected,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WeekCalendarHeaderRow extends StatelessWidget {
  const _WeekCalendarHeaderRow({
    required this.days,
    required this.selectedDay,
    required this.dateForDay,
    required this.dayColumnWidth,
    required this.onDaySelected,
  });

  final List<_WeekDay> days;
  final int selectedDay;
  final DateTime Function(int index) dateForDay;
  final double dayColumnWidth;
  final ValueChanged<int> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      height: _WeekCalendarGrid._headerHeight,
      child: Row(
        children: [
          for (var index = 0; index < days.length; index += 1)
            InkWell(
              onTap: () => onDaySelected(index),
              child: Container(
                width: dayColumnWidth,
                decoration: BoxDecoration(
                  color: index == selectedDay
                      ? colors.primaryContainer.withValues(alpha: 0.24)
                      : Colors.transparent,
                  border: Border(
                    left: BorderSide(color: colors.outlineVariant),
                    bottom: BorderSide(color: colors.outlineVariant),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      days[index].shortName,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${dateForDay(index).day}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeekCalendarSlotRow extends StatelessWidget {
  const _WeekCalendarSlotRow({
    required this.slot,
    required this.days,
    required this.dayColumnWidth,
    required this.slotHeight,
    required this.coursesForSlot,
    required this.onDaySelected,
  });

  final _WeekSlot slot;
  final List<_WeekDay> days;
  final double dayColumnWidth;
  final double slotHeight;
  final List<_ScheduleCourse> Function(int dayIndex, _WeekSlot slot)
  coursesForSlot;
  final ValueChanged<int> onDaySelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: slotHeight,
      child: Row(
        children: [
          for (var dayIndex = 0; dayIndex < days.length; dayIndex += 1)
            _WeekCalendarCell(
              width: dayColumnWidth,
              height: slotHeight,
              courses: coursesForSlot(dayIndex, slot),
              slot: slot,
              onTap: () => onDaySelected(dayIndex),
            ),
        ],
      ),
    );
  }
}

class _WeekCalendarCell extends StatelessWidget {
  const _WeekCalendarCell({
    required this.width,
    required this.height,
    required this.courses,
    required this.slot,
    required this.onTap,
  });

  final double width;
  final double height;
  final List<_ScheduleCourse> courses;
  final _WeekSlot slot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colors.outlineVariant),
            bottom: BorderSide(color: colors.outlineVariant),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: courses.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  children: [
                    _WeekCalendarCourseBlock(course: courses.first, slot: slot),
                    if (courses.length > 1) ...[
                      const SizedBox(height: 3),
                      if (courses.length == 2)
                        _WeekCalendarCourseBlock(course: courses[1], slot: slot)
                      else
                        _WeekHiddenCoursesBadge(count: courses.length - 1),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _WeekHiddenCoursesBadge extends StatelessWidget {
  const _WeekHiddenCoursesBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Text(
      '+$count',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _WeekCalendarCourseBlock extends StatelessWidget {
  const _WeekCalendarCourseBlock({required this.course, required this.slot});

  final _ScheduleCourse course;
  final _WeekSlot slot;

  @override
  Widget build(BuildContext context) {
    final accent = _courseAccent(course.title);

    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                slot.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                course.title,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  height: 1.06,
                ),
              ),
            ],
          ),
        ),
      ),
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
    final sections = textValue(
      course['sections'],
      fallback: textValue(course['slot']),
    );
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

class _AgendaCourseCard extends StatelessWidget {
  const _AgendaCourseCard({required this.course});

  final _ScheduleCourse course;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = _courseAccent(course.title);
    final teacherTag = course.teacher == '-' || course.teacher == '教师未标注'
        ? ''
        : ' #${course.teacher}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: 0.72),
          ),
          boxShadow: [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Positioned.fill(
                right: null,
                child: ColoredBox(
                  color: accent,
                  child: const SizedBox(width: 4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 12, 13, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: course.title),
                                TextSpan(
                                  text: teacherTag,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  height: 1.18,
                                ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _TimePill(
                          start: course.startText,
                          end: course.endText,
                          color: accent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(LucideIcons.mapPin, size: 16, color: accent),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                course.location,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      height: 1.28,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      course.weeks,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}

class _TimePill extends StatelessWidget {
  const _TimePill({
    required this.start,
    required this.end,
    required this.color,
  });

  final String start;
  final String end;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          '$start-$end',
          maxLines: 1,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
