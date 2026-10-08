import 'academic_models.dart';
import 'json_fields.dart';
import 'records.dart';
import 'schedule_planner.dart';

/// What the home-screen widget should show: the class in progress, or the
/// next one, with everything already formatted.
///
/// The snapshot is deliberately presentational — the widget only draws it.
/// Both platforms read the same JSON, so Android and iOS can never drift
/// apart, and neither has to understand the school's schedule format.
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.status,
    required this.title,
    required this.subtitle,
    required this.timeRange,
    this.where = '',
    this.teacher = '',
    this.label = '',
    this.trailing = '',
    this.metaIcons = const [],
    this.metaTexts = const [],
    required this.progress,
    required this.minutes,
    required this.accent,
    required this.updatedAt,
    this.week,
    this.startsAt,
    this.endsAt,
  });

  /// Nothing to show yet (no calendar, term over, schedule not loaded).
  static const WidgetSnapshot empty = WidgetSnapshot(
    status: WidgetStatus.idle,
    title: '',
    subtitle: '',
    timeRange: '',
    progress: null,
    minutes: null,
    accent: 0xFF1D6FD8,
    updatedAt: null,
  );

  final WidgetStatus status;

  /// Course name.
  final String title;

  /// Where, and who teaches it: "实验楼A305 · 王老师". Kept for the
  /// native side to show in one line if it has room to spare.
  final String subtitle;

  /// The room alone, bracket decorations stripped. Own line on the card.
  final String where;

  /// The pill's label: 正在上课 / 下一节.
  final String label;

  /// The pill's right-hand text: 还剩 40 分钟 / 还有 23 分钟.
  final String trailing;

  /// Icon keys for the meta row, one per entry of [metaTexts]: the native
  /// side maps them to its own glyphs (SF Symbols / vector drawables).
  final List<String> metaIcons;

  /// The meta row's values: time, room, teacher.
  final List<String> metaTexts;

  /// The teacher alone.
  final String teacher;

  /// "08:00 - 09:40".
  final String timeRange;

  /// 0–1 through the current class; null when there is no current class.
  final double? progress;

  /// Minutes until the next class starts; null when there is none.
  final int? minutes;

  /// Teaching week, shown as a small tag.
  final int? week;

  /// Skin colour, so the widget matches the app's chosen skin.
  final int accent;

  /// When the snapshot was built (UTC), for the widget's own countdown.
  final DateTime? updatedAt;
  final DateTime? startsAt, endsAt;

  Map<String, Object?> toJson() => {
    'v': 2,
    'startsAt': startsAt?.millisecondsSinceEpoch,
    'endsAt': endsAt?.millisecondsSinceEpoch,
    'status': status.wire,
    'title': title,
    'subtitle': subtitle,
    'where': where,
    'teacher': teacher,
    'label': label,
    'trailing': trailing,
    'metaIcons': metaIcons,
    'metaTexts': metaTexts,
    'timeRange': timeRange,
    'progress': progress,
    'minutes': minutes,
    'week': week,
    'accent': accent,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory WidgetSnapshot.fromJson(Json json) {
    int? rounded(Object? value) => value is num ? value.round() : null;
    List<String> textList(Object? value) => value is List
        ? List.unmodifiable(value.map((e) => e.toString()))
        : const [];
    return WidgetSnapshot(
      startsAt: json['startsAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['startsAt'] as num).toInt(),
              isUtc: true,
            )
          : null,
      endsAt: json['endsAt'] is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['endsAt'] as num).toInt(),
              isUtc: true,
            )
          : null,
      status: WidgetStatus.fromWire(textValue(json['status'])),
      title: textValue(json['title']),
      subtitle: textValue(json['subtitle']),
      where: textValue(json['where']),
      teacher: textValue(json['teacher']),
      label: textValue(json['label']),
      trailing: textValue(json['trailing']),
      metaIcons: textList(json['metaIcons']),
      metaTexts: textList(json['metaTexts']),
      timeRange: textValue(json['timeRange']),
      progress: json['progress'] is num
          ? (json['progress'] as num).toDouble()
          : null,
      minutes: rounded(json['minutes']),
      week: rounded(json['week']),
      accent: rounded(json['accent']) ?? 0xFF1D6FD8,
      updatedAt: DateTime.tryParse(textValue(json['updatedAt'])),
    );
  }
}

enum WidgetStatus {
  /// No data to draw yet.
  idle('idle'),

  /// A class is running now.
  inClass('in_class'),

  /// The next class starts later today (or on the next teaching day).
  upcoming('upcoming'),

  /// Teaching day, but nothing scheduled.
  free('free'),

  /// The day is over.
  done('done');

  const WidgetStatus(this.wire);
  final String wire;

  static WidgetStatus fromWire(String value) => WidgetStatus.values.firstWhere(
    (s) => s.wire == value,
    orElse: () => WidgetStatus.idle,
  );
}

/// Builds the snapshot from the schedule.
///
/// Today only: a widget that reached into tomorrow would answer a question
/// nobody asked, and would sit there wrong all evening. It never needs the
/// network — the schedule is already in memory.
class WidgetSnapshotBuilder {
  const WidgetSnapshotBuilder({
    this.planner = const SchedulePlanner(),
    this.accent = 0xFF1D6FD8,
  });

  final SchedulePlanner planner;

  /// Skin colour for the widget's accent.
  final int accent;

  WidgetSnapshot build({
    required Schedule? schedule,
    required AcademicCalendar? calendar,
    required DateTime now,
  }) {
    if (schedule == null || calendar == null) {
      return _emptyWith(WidgetStatus.idle);
    }
    final today = planner.today(schedule, calendar, now);
    if (today.status == DayScheduleStatus.needsCalendar ||
        today.status == DayScheduleStatus.outsideTerm) {
      return _emptyWith(WidgetStatus.idle, week: today.week);
    }
    final current = today.current;
    if (current != null) {
      final meta = _meta(current.course, _rangeCompact(current));
      final total = current.endsAt.difference(current.startsAt).inSeconds;
      final done = now.difference(current.startsAt).inSeconds;
      final left = current.endsAt.difference(now).inMinutes;
      final head = _headline(current, now);
      return WidgetSnapshot(
        startsAt: current.startsAt,
        endsAt: current.endsAt,
        status: WidgetStatus.inClass,
        title: current.course.title,
        subtitle: _detail(current.course),
        where: widgetWhere(current.course.location),
        teacher: current.course.teacher.trim(),
        label: head.$1,
        trailing: head.$2,
        metaIcons: meta.$1,
        metaTexts: meta.$2,
        timeRange: _range(current),
        progress: total <= 0 ? 1 : (done / total).clamp(0.0, 1.0),
        minutes: left.clamp(0, 24 * 60),
        week: today.week,
        accent: accent,
        updatedAt: now.toUtc(),
      );
    }
    final next = today.next;
    if (next == null) {
      // Nothing left in the window: either the day is done or it is free.
      final status = today.courses.isEmpty
          ? WidgetStatus.free
          : WidgetStatus.done;
      return _emptyWith(status, week: today.week);
    }
    final head = _headline(next, now);
    final meta = _meta(next.course, _rangeCompact(next));
    return WidgetSnapshot(
      startsAt: next.startsAt,
      endsAt: next.endsAt,
      status: WidgetStatus.upcoming,
      title: next.course.title,
      subtitle: _detail(next.course),
      where: widgetWhere(next.course.location),
      teacher: next.course.teacher.trim(),
      label: head.$1,
      trailing: head.$2,
      metaIcons: meta.$1,
      metaTexts: meta.$2,
      timeRange: _range(next),
      progress: null,
      minutes: next.startsAt.difference(now).inMinutes.clamp(0, 7 * 24 * 60),
      week: calendar.weekOn(campusNow(next.startsAt)),
      accent: accent,
      updatedAt: now.toUtc(),
    );
  }

  /// Pre-render each state boundary for seven campus days. A future day's
  /// courses become visible only after its midnight; native code selects a
  /// timestamped entry and interpolates time, never parses school schedules.
  Map<String, Object?> timeline({
    required Schedule? schedule,
    required AcademicCalendar? calendar,
    required DateTime now,
  }) {
    final civil = campusNow(now);
    final midnight = DateTime.utc(
      civil.year,
      civil.month,
      civil.day,
    ).subtract(const Duration(hours: 8));
    final expires = midnight.add(const Duration(days: 7));
    final boundaries = <DateTime>{now.toUtc()};
    if (schedule != null && calendar != null) {
      for (var i = 0; i < 7; i++) {
        final day = midnight.add(Duration(days: i));
        if (day.isAfter(now)) boundaries.add(day);
        for (final course in planner.today(schedule, calendar, day).courses) {
          if (course.startsAt.isAfter(now)) boundaries.add(course.startsAt);
          if (course.endsAt.isAfter(now)) boundaries.add(course.endsAt);
        }
      }
    }
    final sorted = boundaries.toList()..sort();
    return {
      ...build(schedule: schedule, calendar: calendar, now: now).toJson(),
      'expiresAt': expires.millisecondsSinceEpoch,
      'entries': [
        for (final instant in sorted)
          {
            ...build(
              schedule: schedule,
              calendar: calendar,
              now: instant,
            ).toJson(),
            'at': instant.millisecondsSinceEpoch,
          },
      ],
    };
  }

  /// Tidies a room the way the school writes it.
  ///
  /// The scraper glues groups together: "【10号实验楼】软件开发实验室【101】".
  /// Every bracket becomes a separator, so the line reads
  /// "10号实验楼 · 软件开发实验室 · 101". Unlike the week grid, which keeps
  /// only the room number, the widget has room for the building too — but it
  /// still drops a trailing 教室/室 and stays inside [maxRoomChars].
  static String widgetWhere(String raw, {int maxRoomChars = 22}) {
    final parts = <String>[];
    for (final chunk in raw.split(RegExp(r'[【\[\]】]'))) {
      var part = chunk.replaceAll(RegExp(r'\s+'), '').trim();
      if (part.isEmpty) continue;
      // Only a bare room label loses its 室: "101室" → "101", while
      // "软件开发实验室" and "实训室" keep every character.
      part = part.replaceFirst(RegExp(r'^([A-Za-z]?\d+)室$'), r'$1');
      // "101教室" is one room; "教室" alone would be a lost room number.
      if (part.length > 2) {
        part = part.replaceFirst(RegExp(r'^教室'), '');
      }
      if (part.isEmpty || part == '教室') continue;
      // The scraper repeats a cell across slots: keep one copy.
      if (!parts.contains(part)) parts.add(part);
    }
    if (parts.isEmpty) return raw.trim();
    var text = parts.join(' · ');
    if (text.runes.length <= maxRoomChars) return text;
    // Too long for one line: the building and the room number are what
    // matter, so drop the middle first.
    if (parts.length > 2) {
      text = '${parts.first} · ${parts.last}';
      if (text.runes.length <= maxRoomChars) return text;
    }
    return parts.last;
  }

  /// "08:00–09:40", the home card's compact range.
  static String _rangeCompact(CourseOccurrence occurrence) =>
      '${_clockOf(occurrence.startsAt)}–${_clockOf(occurrence.endsAt)}';

  static String _clockOf(DateTime instant) {
    final civil = campusNow(instant);
    return '${civil.hour.toString().padLeft(2, '0')}:'
        '${civil.minute.toString().padLeft(2, '0')}';
  }

  /// The same wording the home card uses, so the two never disagree.
  static String _durationText(Duration duration) {
    final minutes = (duration.inSeconds / 60).ceil();
    if (minutes < 1) return '不到 1 分钟';
    if (minutes < 60) return '$minutes 分钟';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
  }

  static (String, String) _headline(
    CourseOccurrence occurrence,
    DateTime now,
  ) {
    if (occurrence.isOngoing(now)) {
      return (
        '正在上课',
        '还剩 ${_durationText(occurrence.endsAt.difference(now))}',
      );
    }
    final wait = occurrence.startsAt.difference(now);
    return (
      '下一节',
      wait > const Duration(hours: 3)
          ? '${_clockOf(occurrence.startsAt)} 开始'
          : '还有 ${_durationText(wait)}',
    );
  }

  /// Time and teacher for the meta row. The room is not in here: it is the
  /// one value that decides whether a student finds the classroom, so it
  /// gets a line to itself, at the bottom of the card, where a narrow
  /// widget can never cut it short.
  static (List<String>, List<String>) _meta(
    ScheduleCourse course,
    String time,
  ) {
    final icons = <String>[];
    final texts = <String>[];
    void add(String icon, String text) {
      if (text.isEmpty) return;
      icons.add(icon);
      texts.add(text);
    }

    add('schedule', time);
    // The room is deliberately not here: it is the one value that must
    // never be truncated, so it draws on its own line under the meta row.
    add('person', course.teacher.trim());
    return (icons, texts);
  }

  WidgetSnapshot _emptyWith(WidgetStatus status, {int? week}) => WidgetSnapshot(
    status: status,
    title: '',
    subtitle: '',
    timeRange: '',
    progress: null,
    minutes: null,
    week: week,
    accent: accent,
    updatedAt: null,
  );

  static String _detail(ScheduleCourse course) => [
    if (widgetWhere(course.location).isNotEmpty) widgetWhere(course.location),
    if (course.teacher.trim().isNotEmpty) course.teacher.trim(),
  ].join(' · ');

  static String _range(CourseOccurrence occurrence) {
    String clock(DateTime instant) {
      final civil = campusNow(instant);
      final hour = civil.hour.toString().padLeft(2, '0');
      final minute = civil.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    return '${clock(occurrence.startsAt)} - ${clock(occurrence.endsAt)}';
  }
}
