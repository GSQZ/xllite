import 'package:xinli_lite/features/campus/campus.dart';

/// Display helpers. Every date/time shown to the user is campus time
/// (UTC+8), independent of the phone's timezone.

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

String weekdayName(int weekday) => '周${_weekdays[weekday - 1]}';

String _two(int value) => value.toString().padLeft(2, '0');

/// HH:mm of an instant, in campus time.
String clockOf(DateTime instant) {
  final t = campusNow(instant);
  return '${_two(t.hour)}:${_two(t.minute)}';
}

String greetingFor(DateTime now) {
  final hour = campusNow(now).hour;
  if (hour < 5) return '夜深了';
  if (hour < 11) return '早上好';
  if (hour < 13) return '中午好';
  if (hour < 18) return '下午好';
  return '晚上好';
}

String dateLine(DateTime now, {int? week}) {
  final t = campusNow(now);
  final base = '${t.month}月${t.day}日 ${weekdayName(t.weekday)}';
  return week == null ? base : '$base · 第 $week 周';
}

/// Whole campus calendar days from [now] to [instant] (0 = today).
int daysUntil(DateTime instant, DateTime now) {
  final a = campusNow(instant);
  final b = campusNow(now);
  return DateTime.utc(
    a.year,
    a.month,
    a.day,
  ).difference(DateTime.utc(b.year, b.month, b.day)).inDays;
}

String relativeDays(int days) => switch (days) {
  <= 0 => '今天',
  1 => '明天',
  2 => '后天',
  _ => '$days 天后',
};

String durationText(Duration duration) {
  final minutes = (duration.inSeconds / 60).ceil();
  if (minutes < 1) return '不到 1 分钟';
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
}

/// "3-4" → "第3-4节"; values that already say 节 are kept as-is.
String sectionsText(String sections) {
  final value = sections.trim();
  if (value.isEmpty) return '';
  return value.contains('节') ? value : '第$value节';
}

/// "1-16" → "1-16周"; values that already say 周 are kept as-is.
String weeksText(String weeks) {
  final value = weeks.trim();
  if (value.isEmpty) return '';
  return value.contains('周') ? value : '$value周';
}

String updatedText(DateTime? at, DateTime now) {
  if (at == null) return '';
  final t = campusNow(at);
  return daysUntil(at, now) == 0
      ? '更新于 ${clockOf(at)}'
      : '更新于 ${t.month}月${t.day}日 ${clockOf(at)}';
}

/// Joins the non-empty parts with a middle dot.
String joinMeta(Iterable<String> parts) =>
    parts.where((p) => p.trim().isNotEmpty).join(' · ');

/// "2025-2026-2" → "2025-2026 第2学期"; other shapes are kept as-is.
String termText(String term) {
  final m = RegExp(r'^(\d{4})-(\d{4})-(\d)$').firstMatch(term.trim());
  return m == null ? term : '${m[1]}-${m[2]} 第${m[3]}学期';
}

/// Credits/points without trailing zeros: 18.0 → "18", 91.75 → "91.75".
String compactNumber(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Leading "yyyy-MM-dd[ HH:mm[:ss]]" (or with "/") of a school timestamp, as
/// campus civil time in UTC fields. Null when the text has another shape.
DateTime? parseSchoolTimestamp(String text) {
  final m = RegExp(
    r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?',
  ).firstMatch(text.trim());
  if (m == null) return null;
  int part(int i) => int.parse(m[i] ?? '0');
  final value = DateTime.utc(
    part(1),
    part(2),
    part(3),
    part(4),
    part(5),
    part(6),
  );
  return value.month == part(2) && value.day == part(3) ? value : null;
}

/// "10月8日 周四" for a campus civil date (UTC fields).
String civilDateText(DateTime civil) =>
    '${civil.month}月${civil.day}日 ${weekdayName(civil.weekday)}';

/// Short form of a room label for narrow spaces, e.g. 教3-201 → 3-201,
/// 教学楼A305 → A305, 3-201教室 → 3-201, 体育馆-羽毛球馆-3号场 → 体育馆.
///
/// Only drops a leading building word when a room number follows it, so
/// labels such as 教材室 or 9#312 are left alone; a segment is only kept
/// when the result would still be too long, and the full label stays
/// visible in the course detail sheet.
String compactLocation(String value) {
  var text = value.trim().replaceAll(RegExp(r'\s+'), '');
  if (text.isEmpty) return text;
  // School labels repeat a building, lab name and finally the actual room.
  // Prefer that final room identifier, rather than truncating the building
  // prefix and losing the only information needed to find the classroom.
  final brackets = RegExp(r'[【\[]([^】\]]+)[】\]]').allMatches(text).toList();
  if (brackets.isNotEmpty) {
    final last = brackets.last;
    final trailing = text.substring(last.end);
    final candidate = trailing.isNotEmpty ? trailing : last[1]!;
    if (RegExp(r'\d').hasMatch(candidate)) text = candidate;
  }
  text = text.replaceAll('工科实训楼', '实训');
  text = text.replaceFirst(RegExp(r'教室$'), '');
  text = text.replaceFirstMapped(RegExp(r'(\d)室$'), (m) => m[1]!);
  for (final prefix in const ['教学楼', '教学区', '实验楼', '综合楼', '教']) {
    if (!text.startsWith(prefix) || text.length == prefix.length) continue;
    final rest = text.substring(prefix.length);
    if (RegExp(r'^[A-Za-z]?\d').hasMatch(rest)) {
      text = rest;
      break;
    }
  }
  if (text.runes.length > 8) {
    final head = text.split(RegExp(r'[-—·/、()（）]')).first;
    if (head.runes.length >= 2) text = head;
  }
  return text;
}
