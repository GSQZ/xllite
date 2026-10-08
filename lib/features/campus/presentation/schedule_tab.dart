import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xinli_lite/features/auth/auth.dart';
import 'package:xinli_lite/features/campus/campus.dart';

import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/motion.dart';
import '../../../shared/widgets/segmented.dart';
import '../../../shared/widgets/frosted.dart';
import '../../../shared/widgets/state_panel.dart';
import '../../../shared/widgets/status_banner.dart';
import 'campus_format.dart';
import 'detail_sheet.dart';
import 'section_parts.dart';
import 'signed_in_memo.dart';

enum _Mode { day, week }

/// Timetable with two views: 当日 (one day as a timeline, with a week strip
/// to pick the day) and 周视图 (the whole teaching week as a grid).
///
/// Every day shown goes through [SchedulePlanner.today], so holidays and
/// make-up days from the calendar apply in both views. Without a confirmed
/// calendar the views fall back to weekday + section order and say so.
class ScheduleTab extends StatefulWidget {
  const ScheduleTab({super.key, required this.auth, required this.campus});

  final AuthController auth;
  final CampusController campus;

  @override
  State<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<ScheduleTab> {
  late final Listenable _listenable = Listenable.merge([
    widget.auth,
    widget.campus.schedule,
    widget.campus.home,
  ]);
  final _memo = SignedInMemo<ResourceState<Schedule>>();

  var _mode = _Mode.day;

  /// Null follows the current teaching week / today.
  int? _week;
  int? _weekday;

  /// Direction of the last day/week step, for the slide transition.
  var _direction = 0;

  Future<void> _refresh() => widget.campus.loadSchedule(
    term: widget.campus.selectedTerm,
    refresh: true,
  );

  void _retry() => widget.campus.loadSchedule(term: widget.campus.selectedTerm);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _listenable,
      builder: (context, _) {
        final state = _memo.read(
          signedIn: widget.auth.state.isAuthenticated,
          live: () => widget.campus.schedule.state,
        );
        return _build(context, state);
      },
    );
  }

  Widget _build(BuildContext context, ResourceState<Schedule> state) {
    final top = MediaQuery.paddingOf(context).top;
    final schedule = state.data;
    if (schedule == null) {
      final failure = state.failure;
      return Padding(
        padding: EdgeInsets.only(top: top),
        child: failure != null && !state.isLoading
            ? StatePanel(
                icon: Icons.cloud_off_rounded,
                tone: PanelTone.error,
                title: '课表加载失败',
                message: failure.message,
                actions: [
                  FilledButton(onPressed: _retry, child: const Text('重试')),
                ],
              )
            : const StatePanel(loading: true, title: '正在同步课表…'),
      );
    }

    final now = DateTime.now();
    final model = _TermModel(
      schedule: schedule,
      calendar: schedule.calendar ?? widget.campus.home.calendar,
      now: now,
    );
    final week = model.clampWeek(_week ?? model.currentWeek ?? 1);
    final weekday = _weekday ?? model.today.weekday;
    final width = MediaQuery.sizeOf(context).width;
    final side = math.max(AppSpacing.gutterFor(width), (width - 720) / 2);

    final Widget body = switch (_mode) {
      _Mode.day => _DayView(
        key: ValueKey(('day', week, weekday)),
        model: model,
        week: week,
        weekday: weekday,
      ),
      _Mode.week => _WeekGrid(
        key: ValueKey(('week', week)),
        model: model,
        week: week,
      ),
    };

    return Padding(
      padding: EdgeInsets.only(top: top),
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          key: const Key('schedule.scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            top: AppSpacing.md,
            bottom: 20 + MediaQuery.paddingOf(context).bottom,
          ),
          children:
              <Widget>[
                    _Header(
                      model: model,
                      week: week,
                      onWeek: model.hasCalendar ? _stepWeek : null,
                      onThisWeek: () => setState(() {
                        _direction = (model.currentWeek ?? week) > week
                            ? 1
                            : -1;
                        _week = null;
                        _weekday = null;
                      }),
                    ),
                    if (state.isStale) ...[
                      const SizedBox(height: AppSpacing.sm),
                      StaleNote(
                        text:
                            '${updatedText(state.updatedAt, now)} · 刷新失败，下拉重试',
                      ),
                    ],
                    if (!model.hasCalendar) ...[
                      const SizedBox(height: AppSpacing.md),
                      const StatusBanner(
                        tone: StatusTone.info,
                        message: '本学期校历尚未配置，暂按星期排列，未按教学周筛选。',
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    AppSegmented(
                      key: const Key('schedule.mode'),
                      labels: const ['当日', '周视图'],
                      index: _mode.index,
                      onChanged: (i) {
                        if (i == _mode.index) return;
                        HapticFeedback.selectionClick();
                        setState(() {
                          _direction = 0;
                          _mode = _Mode.values[i];
                        });
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    GestureDetector(
                      key: const Key('schedule.viewport'),
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v.abs() < 300) return;
                        final step = v < 0 ? 1 : -1;
                        if (_mode == _Mode.day) {
                          _stepDay(model, week, weekday, step);
                        }
                      },
                      // Two levels: the mode switch fades the whole view
                      // (date strip included) as one unit; inside it only
                      // the day list / week grid changes.
                      child: _switcher(
                        context,
                        KeyedSubtree(
                          key: ValueKey(_mode),
                          child: switch (_mode) {
                            _Mode.day => Padding(
                              padding: EdgeInsets.symmetric(horizontal: side),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _DayStrip(
                                    model: model,
                                    week: week,
                                    selected: weekday,
                                    onSelected: (d) {
                                      if (d == weekday) return;
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        _direction = d > weekday ? 1 : -1;
                                        _week = week;
                                        _weekday = d;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: AppSpacing.lg),
                                  _switcher(context, body),
                                ],
                              ),
                            ),
                            _Mode.week => _switcher(context, body),
                          },
                        ),
                        direction: 0,
                      ),
                    ),
                    if (schedule.courses.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: AppSpacing.xl),
                        child: StatePanel(
                          icon: Icons.event_available_rounded,
                          title: '本学期暂无课程',
                        ),
                      ),
                  ]
                  .map(
                    (child) => child.key == const Key('schedule.viewport')
                        ? child
                        : Padding(
                            padding: EdgeInsets.symmetric(horizontal: side),
                            child: child,
                          ),
                  )
                  .toList(),
        ),
      ),
    );
  }

  /// Sequential fade (old fully out, then new in) so two views never show
  /// through each other.
  Widget _switcher(BuildContext context, Widget child, {int? direction}) {
    final dir = direction ?? _direction;
    return AnimatedSwitcher(
      duration: AppMotion.reduced(context)
          ? Duration.zero
          : const Duration(milliseconds: 460),
      switchInCurve: Curves.linear,
      switchOutCurve: Curves.linear,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          for (final p in previous)
            IgnorePointer(child: ExcludeSemantics(child: p)),
          ?current,
        ],
      ),
      transitionBuilder: (c, animation) =>
          sequentialTransition(c, animation, direction: dir, distance: 40),
      child: child,
    );
  }

  void _stepWeek(int step) {
    final schedule = widget.campus.schedule.state.data;
    if (schedule == null) return;
    final model = _TermModel(
      schedule: schedule,
      calendar: schedule.calendar ?? widget.campus.home.calendar,
      now: DateTime.now(),
    );
    final current = model.clampWeek(_week ?? model.currentWeek ?? 1);
    final next = model.clampWeek(current + step);
    if (next == current) return;
    HapticFeedback.selectionClick();
    setState(() {
      _direction = step;
      _week = next;
    });
  }

  void _stepDay(_TermModel model, int week, int weekday, int step) {
    var d = weekday + step;
    var w = week;
    if (d < 1 || d > 7) {
      if (!model.hasCalendar) return;
      final nw = model.clampWeek(w + step);
      if (nw == w) return;
      w = nw;
      d = d < 1 ? 7 : 1;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _direction = step;
      _week = w;
      _weekday = d;
    });
  }
}

// ---------------------------------------------------------------------------
// Model

/// One timetable row: a calendar section block, or a bare section number
/// when there is no calendar.
class _Row {
  const _Row(this.label, this.start, this.end);
  final String label;

  /// Campus minutes, or null without a calendar.
  final int? start, end;
}

class _Block {
  const _Block({
    required this.course,
    required this.weekday,
    required this.first,
    required this.last,
    this.occurrence,
  });
  final ScheduleCourse course;
  final int weekday, first, last;
  final CourseOccurrence? occurrence;
}

class _TermModel {
  _TermModel({
    required this.schedule,
    required this.calendar,
    required this.now,
  }) : today = _civilDay(campusNow(now)) {
    hasCalendar = calendar != null && calendar!.term == schedule.term;
    currentWeek = hasCalendar ? calendar!.weekOn(today) : null;
  }

  final Schedule schedule;
  final AcademicCalendar? calendar;
  final DateTime now;

  /// Campus civil date, UTC fields.
  final DateTime today;
  late final bool hasCalendar;
  late final int? currentWeek;

  int clampWeek(int week) =>
      hasCalendar ? week.clamp(1, calendar!.weekCount) : 1;

  static DateTime _civilDay(DateTime c) => DateTime.utc(c.year, c.month, c.day);

  DateTime? dateOf(int week, int weekday) => hasCalendar
      ? calendar!.firstMonday.add(Duration(days: (week - 1) * 7 + weekday - 1))
      : null;

  bool isToday(int week, int weekday) {
    final d = dateOf(week, weekday);
    return d == null ? weekday == today.weekday : d == today;
  }

  /// The planner's view of a day. Today uses the real clock so the current
  /// class is known; other days use campus noon.
  DaySchedule? plan(int week, int weekday) {
    final d = dateOf(week, weekday);
    if (d == null) return null;
    final instant = d == today ? now : DateTime.utc(d.year, d.month, d.day, 4);
    return const SchedulePlanner().today(schedule, calendar, instant);
  }

  CalendarDateOverride? overrideOn(int week, int weekday) {
    final d = dateOf(week, weekday);
    if (d == null) return null;
    return calendar!.dateOverrides
        .where((o) => _civilDay(o.date) == d)
        .firstOrNull;
  }

  /// Courses of a weekday without a calendar, by first section.
  List<ScheduleCourse> plainDay(int weekday) {
    int first(ScheduleCourse c) =>
        parseSchoolNumbers(c.sections)?.fold<int>(99, math.min) ?? 99;
    return schedule.courses
        .where((c) => courseWeekday(c.day) == weekday)
        .toList()
      ..sort((a, b) => first(a).compareTo(first(b)));
  }

  late final List<_Row> rows = () {
    if (hasCalendar && calendar!.sections.isNotEmpty) {
      final sorted = [...calendar!.sections]
        ..sort((a, b) => a.section.compareTo(b.section));
      return [
        for (final s in sorted)
          _Row(
            s.section == s.endSection
                ? '${s.section}'
                : '${s.section}-${s.endSection}',
            s.startMinute,
            s.endMinute,
          ),
      ];
    }
    var max = 0;
    for (final c in schedule.courses) {
      final n = parseSchoolNumbers(c.sections);
      if (n != null && n.isNotEmpty) max = math.max(max, n.reduce(math.max));
    }
    return [for (var i = 1; i <= math.max(max, 8); i++) _Row('$i', null, null)];
  }();

  List<_Block> blocks(int week) {
    final result = <_Block>[];
    if (hasCalendar) {
      for (var d = 1; d <= 7; d++) {
        final day = plan(week, d);
        for (final o in day?.courses ?? const <CourseOccurrence>[]) {
          final s = _minute(o.startsAt), e = _minute(o.endsAt);
          final hit = [
            for (var i = 0; i < rows.length; i++)
              if (rows[i].start! < e && rows[i].end! > s) i,
          ];
          if (hit.isEmpty) continue;
          result.add(
            _Block(
              course: o.course,
              weekday: d,
              first: hit.first,
              last: hit.last,
              occurrence: o,
            ),
          );
        }
      }
      return result;
    }
    for (final c in schedule.courses) {
      final d = courseWeekday(c.day);
      final n = parseSchoolNumbers(c.sections);
      if (d == null || n == null || n.isEmpty) continue;
      result.add(
        _Block(
          course: c,
          weekday: d,
          first: n.reduce(math.min) - 1,
          last: math.min(n.reduce(math.max), rows.length) - 1,
        ),
      );
    }
    return result;
  }

  /// Courses whose time could not be placed for that week.
  int unresolved(int week) {
    if (!hasCalendar) {
      return schedule.courses
          .where(
            (c) =>
                courseWeekday(c.day) == null ||
                (parseSchoolNumbers(c.sections)?.isEmpty ?? true),
          )
          .length;
    }
    var n = 0;
    for (var d = 1; d <= 7; d++) {
      n += plan(week, d)?.unresolved.length ?? 0;
    }
    return n;
  }

  int classCount(int week, int weekday) => hasCalendar
      ? (plan(week, weekday)?.courses.length ?? 0)
      : plainDay(weekday).length;
}

int _minute(DateTime instant) {
  final c = campusNow(instant);
  return c.hour * 60 + c.minute;
}

String _hm(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

// ---------------------------------------------------------------------------
// Course colours

/// Soft course hues: a light fill and a readable ink in each theme. The same
/// course always gets the same hue.
const _hues = [
  (Color(0xFF1D6FD8), Color(0xFF8AB4FF)),
  (Color(0xFF0B8586), Color(0xFF6FD6D2)),
  (Color(0xFF5B5BD6), Color(0xFFB2B0FF)),
  (Color(0xFFB86E00), Color(0xFFFFC266)),
  (Color(0xFFC2416B), Color(0xFFFF9EBB)),
  (Color(0xFF2E8540), Color(0xFF8CD99B)),
  (Color(0xFF8A4FC7), Color(0xFFD3A8FF)),
  (Color(0xFF00788A), Color(0xFF7FD3E3)),
];

Color courseInk(BuildContext context, ScheduleCourse course) {
  final hue = _hues[course.title.hashCode.abs() % _hues.length];
  return Theme.of(context).brightness == Brightness.dark ? hue.$2 : hue.$1;
}

Color courseFill(BuildContext context, ScheduleCourse course) =>
    courseInk(context, course).withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.11,
    );

void _showCourse(BuildContext context, ScheduleCourse c, CourseOccurrence? o) {
  showDetailSheet(
    context,
    title: c.title,
    highlightLabel: o == null ? null : '时间',
    highlight: o == null
        ? null
        : '${civilDateText(campusNow(o.startsAt))} ${clockOf(o.startsAt)}–${clockOf(o.endsAt)}',
    rows: [
      ('地点', c.location),
      ('节次', sectionsText(c.sections)),
      ('周次', weeksText(c.weeks)),
      ('星期', c.day),
      ('教师', c.teacher),
    ],
  );
}

// ---------------------------------------------------------------------------
// Header & controls

class _Header extends StatelessWidget {
  const _Header({
    required this.model,
    required this.week,
    required this.onWeek,
    required this.onThisWeek,
  });

  final _TermModel model;
  final int week;
  final ValueChanged<int>? onWeek;
  final VoidCallback onThisWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final schedule = model.schedule;
    final term = schedule.termLabel.isNotEmpty
        ? schedule.termLabel
        : termText(schedule.term);
    final current = model.currentWeek;
    final isCurrent = current == week;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  '课表',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                term,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (onWeek != null)
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const Key('schedule.prevWeek'),
                  tooltip: '上一周',
                  visualDensity: VisualDensity.compact,
                  onPressed: week > 1 ? () => onWeek!(-1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Semantics(
                  button: !isCurrent && current != null,
                  label: isCurrent ? '第 $week 周，本周' : '第 $week 周，回到本周',
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: isCurrent || current == null ? null : onThisWeek,
                    child: AnimatedSwitcher(
                      duration: AppMotion.medium,
                      child: Column(
                        key: ValueKey(week),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '第 $week 周',
                            key: const Key('schedule.week'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          Text(
                            isCurrent
                                ? '本周'
                                : current == null
                                ? '非教学周'
                                : '回到本周',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isCurrent
                                  ? scheme.onSurfaceVariant
                                  : scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('schedule.nextWeek'),
                  tooltip: '下一周',
                  visualDensity: VisualDensity.compact,
                  onPressed: week < model.calendar!.weekCount
                      ? () => onWeek!(1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Day view

class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.model,
    required this.week,
    required this.selected,
    required this.onSelected,
  });

  final _TermModel model;
  final int week;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        for (var d = 1; d <= 7; d++)
          Expanded(
            child: Builder(
              builder: (context) {
                final on = d == selected;
                final today = model.isToday(week, d);
                final date = model.dateOf(week, d);
                final count = model.classCount(week, d);
                final ink = on
                    ? scheme.onPrimary
                    : today
                    ? scheme.primary
                    : scheme.onSurface;
                return Semantics(
                  button: true,
                  selected: on,
                  label:
                      '${weekdayName(d)}${date == null ? '' : ' ${date.month}月${date.day}日'}${today ? '，今天' : ''}，$count 节课',
                  excludeSemantics: true,
                  child: InkWell(
                    key: Key('schedule.day.$d'),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    onTap: () => onSelected(d),
                    child: AnimatedContainer(
                      duration: AppMotion.medium,
                      curve: AppMotion.curve,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: on ? scheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        boxShadow: on
                            ? [
                                BoxShadow(
                                  color: scheme.primary.withValues(alpha: 0.28),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            weekdayName(d).substring(1),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: on
                                  ? scheme.onPrimary.withValues(alpha: 0.85)
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            date == null
                                ? weekdayName(d).substring(1)
                                : '${date.day}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: ink,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Dots: how busy the day is (up to three).
                          SizedBox(
                            height: 4,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                for (var i = 0; i < math.min(count, 3); i++)
                                  Container(
                                    width: 4,
                                    height: 4,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: on
                                          ? scheme.onPrimary
                                          : scheme.primary.withValues(
                                              alpha: 0.6,
                                            ),
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
              },
            ),
          ),
      ],
    );
  }
}

class _DayView extends StatelessWidget {
  const _DayView({
    super.key,
    required this.model,
    required this.week,
    required this.weekday,
  });

  final _TermModel model;
  final int week;
  final int weekday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = model.dateOf(week, weekday);
    final today = model.isToday(week, weekday);
    final title = date == null
        ? weekdayName(weekday)
        : '${civilDateText(date)}${today ? ' · 今天' : ''}';

    final children = <Widget>[];
    String? empty;
    String? note;

    if (!model.hasCalendar) {
      final courses = model.plainDay(weekday);
      for (final c in courses) {
        children.add(_ClassRow(course: c, start: null, end: null));
      }
      if (courses.isEmpty) empty = '这天没有课';
    } else {
      final plan = model.plan(week, weekday)!;
      final override = model.overrideOn(week, weekday);
      if (override != null) {
        note = override.scheduleDate == null
            ? (override.reason.isEmpty ? '停课' : '${override.reason} · 停课')
            : '${override.reason.isEmpty ? '调课' : override.reason} · 按'
                  '${civilDateText(override.scheduleDate!)}的课表上课';
      }
      if (date!.isBefore(model.calendar!.classesStartOn)) {
        empty = '尚未开课';
      }
      for (final o in plan.courses) {
        children.add(
          _ClassRow(
            course: o.course,
            occurrence: o,
            start: clockOf(o.startsAt),
            end: clockOf(o.endsAt),
            state: !today
                ? _ClassState.normal
                : o.isOngoing(model.now)
                ? _ClassState.current
                : o.endsAt.isBefore(model.now)
                ? _ClassState.past
                : _ClassState.normal,
          ),
        );
      }
      for (final c in plan.unresolved) {
        children.add(
          _ClassRow(course: c, start: '待定', end: null, unresolved: true),
        );
      }
      if (children.isEmpty) {
        empty ??= override?.scheduleDate == null && override != null
            ? '今日停课'
            : '这天没有课';
      }
    }

    // A fixed day viewport keeps empty and busy days the same height. Long
    // timetables scroll inside it instead of resizing the swipe transition.
    final viewportHeight = math.max(
      320.0,
      MediaQuery.sizeOf(context).height -
          MediaQuery.paddingOf(context).vertical -
          300,
    );
    return SizedBox(
      key: const Key('schedule.dayViewport'),
      height: viewportHeight,
      child: SingleChildScrollView(
        key: ValueKey(('schedule.dayScroll', week, weekday)),
        child: Column(
          key: const Key('schedule.dayList'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: title,
              trailing: children.isEmpty ? null : '${children.length} 节',
            ),
            if (note != null) ...[
              const SizedBox(height: AppSpacing.sm),
              StatusBanner(tone: StatusTone.info, message: note),
            ],
            const SizedBox(height: AppSpacing.md),
            if (empty != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: Column(
                  children: [
                    Icon(
                      Icons.free_breakfast_outlined,
                      size: 40,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      empty,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            else
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.sm + 2),
                children[i],
              ],
          ],
        ),
      ),
    );
  }
}

enum _ClassState { normal, current, past }

class _ClassRow extends StatelessWidget {
  const _ClassRow({
    required this.course,
    required this.start,
    required this.end,
    this.occurrence,
    this.state = _ClassState.normal,
    this.unresolved = false,
  });

  final ScheduleCourse course;
  final CourseOccurrence? occurrence;
  final String? start, end;
  final _ClassState state;
  final bool unresolved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = courseInk(context, course);
    final current = state == _ClassState.current;
    final meta = joinMeta([
      course.location,
      sectionsText(course.sections),
      if (unresolved || occurrence == null) weeksText(course.weeks),
      course.teacher,
    ]);
    return AnimatedOpacity(
      duration: AppMotion.long,
      opacity: state == _ClassState.past ? 0.5 : 1,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (start != null)
              SizedBox(
                width: 50,
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        start!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: current ? scheme.primary : null,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (end != null)
                        Text(
                          end!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: FrostedCard(
                radius: AppRadius.lg,
                edge: current
                    ? BorderSide(
                        color: scheme.primary.withValues(alpha: 0.7),
                        width: 1.5,
                      )
                    : null,
                child: InkWell(
                  onTap: () => _showCourse(context, course, occurrence),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(width: 4, color: ink),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md + 2,
                            AppSpacing.md,
                            AppSpacing.md,
                            AppSpacing.md,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      course.title,
                                      style: theme.textTheme.titleSmall,
                                    ),
                                  ),
                                  if (current)
                                    _Tag(label: '进行中', color: scheme.primary),
                                  if (unresolved)
                                    _Tag(
                                      label: '时间待定',
                                      color: StatusColors.of(context).warning,
                                    ),
                                ],
                              ),
                              if (meta.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  meta,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              if (current && occurrence != null) ...[
                                const SizedBox(height: AppSpacing.sm),
                                _Progress(occurrence: occurrence!),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.occurrence});

  final CourseOccurrence occurrence;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final total = occurrence.endsAt.difference(occurrence.startsAt).inSeconds;
    final value = total <= 0
        ? 1.0
        : (now.difference(occurrence.startsAt).inSeconds / total).clamp(
            0.0,
            1.0,
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 4,
        semanticsLabel: '本节课已进行 ${(value * 100).round()}%',
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsetsDirectional.only(start: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Week grid

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({super.key, required this.model, required this.week});

  final _TermModel model;
  final int week;

  static const _labelWidth = 32.0;
  static const _headerHeight = 46.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = model.rows;
    final blocks = model.blocks(week);
    final weekend = blocks.any((b) => b.weekday >= 6);
    final days = weekend ? 7 : 5;
    final textScaler = MediaQuery.textScalerOf(context);
    final rowHeight = math.max(50.0, textScaler.scale(50));
    final minLaneWidth = textScaler.scale(days == 7 ? 44 : 52);
    final rowTops = <double>[];
    var bodyHeight = 0.0;
    // Every row is the same height; breaks are not drawn as extra space.
    for (var i = 0; i < rows.length; i++) {
      rowTops.add(bodyHeight);
      bodyHeight += rowHeight;
    }
    final unresolved = model.unresolved(week);

    // Only connected groups of overlapping classes share lanes. An isolated
    // afternoon class keeps the full day width even if the morning conflicts.
    final lanes = <_Block, (int, int)>{};
    for (var d = 1; d <= days; d++) {
      final day = blocks.where((b) => b.weekday == d).toList()
        ..sort((a, b) {
          final start = a.first.compareTo(b.first);
          return start != 0 ? start : a.last.compareTo(b.last);
        });
      var first = 0;
      while (first < day.length) {
        var after = first + 1;
        var lastRow = day[first].last;
        while (after < day.length && day[after].first <= lastRow) {
          lastRow = math.max(lastRow, day[after].last);
          after++;
        }
        final group = day.sublist(first, after);
        final ends = <int>[];
        final lane = <_Block, int>{};
        for (final b in group) {
          var i = ends.indexWhere((e) => e < b.first);
          if (i < 0) {
            ends.add(b.last);
            i = ends.length - 1;
          } else {
            ends[i] = b.last;
          }
          lane[b] = i;
        }
        for (final b in group) {
          lanes[b] = (lane[b]!, ends.length);
        }
        first = after;
      }
    }

    return Column(
      key: const Key('schedule.grid'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final gutter = math.max(12.0, (constraints.maxWidth - 720) / 2);
            final availableWidth = constraints.maxWidth - gutter * 2;
            final dayWidths = [
              for (var d = 1; d <= days; d++)
                minLaneWidth *
                    blocks
                        .where((b) => b.weekday == d)
                        .fold<int>(1, (max, b) => math.max(max, lanes[b]!.$2)),
            ];
            final minWidth = _labelWidth + dayWidths.reduce((a, b) => a + b);
            final extra = math.max(0.0, availableWidth - minWidth) / days;
            for (var i = 0; i < days; i++) {
              dayWidths[i] += extra;
            }
            final lefts = <double>[_labelWidth];
            for (final width in dayWidths) {
              lefts.add(lefts.last + width);
            }
            final gridWidth = lefts.last;
            final height = _headerHeight + bodyHeight;
            final nowY = _nowOffset(rows, rowHeight, rowTops);
            final todayCol = [
              for (var d = 1; d <= days; d++)
                if (model.isToday(week, d)) d,
            ].firstOrNull;

            final grid = SizedBox(
              width: gridWidth,
              height: height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    children: [
                      // Today's column wash.
                      if (todayCol != null && model.hasCalendar)
                        Positioned(
                          left: lefts[todayCol - 1],
                          top: 0,
                          width: dayWidths[todayCol - 1],
                          height: height,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.035),
                            ),
                          ),
                        ),
                      // Header: weekday + date.
                      for (var d = 1; d <= days; d++)
                        Positioned(
                          left: lefts[d - 1],
                          top: 0,
                          width: dayWidths[d - 1],
                          height: _headerHeight,
                          child: _DayHead(
                            weekday: d,
                            date: model.dateOf(week, d),
                            today: model.hasCalendar && d == todayCol,
                          ),
                        ),
                      // Row labels and hairlines.
                      for (var d = 0; d < days; d++)
                        Positioned(
                          left: lefts[d],
                          top: 0,
                          bottom: 0,
                          width: 0.5,
                          child: ColoredBox(
                            color: scheme.outlineVariant.withValues(
                              alpha: 0.22,
                            ),
                          ),
                        ),
                      for (var i = 0; i < rows.length; i++) ...[
                        Positioned(
                          left: 0,
                          top: _headerHeight + rowTops[i],
                          width: _labelWidth,
                          height: rowHeight,
                          child: _RowLabel(row: rows[i]),
                        ),
                        Positioned(
                          left: _labelWidth,
                          right: 0,
                          top: _headerHeight + rowTops[i],
                          height: 0.5,
                          child: ColoredBox(
                            color: scheme.outlineVariant.withValues(
                              alpha: i.isEven ? 0.4 : 0.18,
                            ),
                          ),
                        ),
                      ],
                      // Course blocks.
                      for (final b in blocks.where((b) => b.weekday <= days))
                        Positioned(
                          left:
                              lefts[b.weekday - 1] +
                              lanes[b]!.$1 *
                                  dayWidths[b.weekday - 1] /
                                  lanes[b]!.$2 +
                              2,
                          top: _headerHeight + rowTops[b.first] + 2,
                          width: dayWidths[b.weekday - 1] / lanes[b]!.$2 - 4,
                          height:
                              rowTops[b.last] -
                              rowTops[b.first] +
                              rowHeight -
                              4,
                          child: _BlockTile(
                            key: ValueKey((
                              'schedule.block',
                              b.weekday,
                              b.first,
                              b.course.title,
                            )),
                            block: b,
                            current:
                                b.occurrence != null &&
                                b.occurrence!.isOngoing(model.now),
                          ),
                        ),
                      // Now line, on this week's today column.
                      if (nowY != null && todayCol != null)
                        Positioned(
                          left: lefts[todayCol - 1] - 3,
                          width: dayWidths[todayCol - 1] + 3,
                          top: _headerHeight + nowY - 3,
                          height: 6,
                          child: IgnorePointer(
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: scheme.error,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    height: 1.5,
                                    color: scheme.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (gridWidth > availableWidth + 0.5)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      0,
                      gutter,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      '左右滑动查看完整课表',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                SingleChildScrollView(
                  key: const Key('schedule.weekScroll'),
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: gutter),
                  child: grid,
                ),
              ],
            );
          },
        ),
        if (unresolved > 0) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            '另有 $unresolved 门课程时间无法确定，可在「当日」中查看。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: StatusColors.of(context).warning,
            ),
          ),
        ],
      ],
    );
  }

  /// Pixel offset of "now" within the rows, when today is in this week.
  double? _nowOffset(List<_Row> rows, double rowHeight, List<double> rowTops) {
    if (!model.hasCalendar || model.currentWeek != week) return null;
    final m = _minute(model.now);
    if (rows.isEmpty ||
        rows.first.start == null ||
        m < rows.first.start! ||
        m > rows.last.end!) {
      return null;
    }
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (m < r.start!) return rowTops[i]; // between rows
      if (m <= r.end!) {
        return rowTops[i] + (m - r.start!) / (r.end! - r.start!) * rowHeight;
      }
    }
    return null;
  }
}

class _DayHead extends StatelessWidget {
  const _DayHead({
    required this.weekday,
    required this.date,
    required this.today,
  });

  final int weekday;
  final DateTime? date;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = today ? scheme.primary : scheme.onSurfaceVariant;
    // Fitted: the header row has a fixed height, so large system text
    // scales the labels down instead of overflowing.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              weekdayName(weekday),
              style: theme.textTheme.labelMedium?.copyWith(
                color: today ? scheme.primary : scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (date != null)
              Text(
                '${date!.month}/${date!.day}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel({required this.row});

  final _Row row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          children: [
            Text(
              row.label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (row.start != null)
              Text(
                _hm(row.start!),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9.5,
                  color: muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BlockTile extends StatelessWidget {
  const _BlockTile({super.key, required this.block, required this.current});

  final _Block block;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final course = block.course;
    final ink = courseInk(context, course);
    return Material(
      color: Color.alphaBlend(
        courseFill(context, course),
        theme.colorScheme.surface,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: current ? BorderSide(color: ink, width: 1.5) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showCourse(context, course, block.occurrence),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: LayoutBuilder(
            builder: (context, c) {
              final titleStyle = theme.textTheme.labelMedium?.copyWith(
                color: ink,
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
                height: 1.3,
              );
              final location = compactLocation(course.location);
              final locationStyle = theme.textTheme.labelSmall?.copyWith(
                color: ink.withValues(alpha: 0.9),
                fontSize: 10.5,
                height: 1.25,
                fontWeight: FontWeight.w500,
              );
              // Reserve the room's actual wrapped height before fitting the
              // title. Never shrink a long room into an unreadable single line.
              final roomPainter = TextPainter(
                text: TextSpan(text: location, style: locationStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                maxLines: 1,
                ellipsis: '…',
              )..layout(maxWidth: c.maxWidth);
              final roomHeight = location.isEmpty ? 0.0 : roomPainter.height;
              roomPainter.dispose();
              final gap = location.isEmpty ? 0.0 : 5.0;
              final lineHeight =
                  MediaQuery.textScalerOf(context).scale(11.5) * 1.3;
              final lines = math.max(
                1,
                ((c.maxHeight - roomHeight - gap) / lineHeight).floor(),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        course.title,
                        maxLines: lines,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                    ),
                  ),
                  if (location.isNotEmpty) ...[
                    SizedBox(height: gap),
                    Text(
                      location,
                      maxLines: 1,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                      style: locationStyle,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
