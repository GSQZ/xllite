import Foundation
import WidgetKit

/// The snapshot the app writes and the widget reads.
///
/// Exactly the same JSON the Android widget uses, so the two platforms can
/// never drift apart — and neither has to understand the school's timetable.
struct WidgetSnapshot: Codable {
  enum Status: String, Codable {
    case idle
    case inClass = "in_class"
    case upcoming
    case free
    case done
  }

  var status: Status
  var title: String
  var subtitle: String
  var timeRange: String
  /// The room on its own, already tidied by the app. `where` is a Swift
  /// keyword, so it is decoded from the JSON key of that name.
  var room: String?
  var teacher: String?
  /// The pill's label (正在上课 / 下一节) and its right-hand countdown.
  var label: String?
  var trailing: String?
  /// The meta row: icon keys and their values, in the order to draw them.
  var metaIcons: [String]?
  var metaTexts: [String]?
  var progress: Double?
  var minutes: Int?
  var week: Int?
  var accent: Int
  var at: Double?
  var startsAt: Double?
  var endsAt: Double?

  private enum CodingKeys: String, CodingKey {
    case status, title, subtitle, timeRange, teacher, progress, minutes
    case week, accent, at, startsAt, endsAt, label, trailing, metaIcons, metaTexts
    case room = "where"
  }
}

extension WidgetSnapshot {
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    // A snapshot is a live payload: a missing key must read as "unknown",
    // never throw away the whole card.
    status = (try? c.decode(Status.self, forKey: .status)) ?? .idle
    title = (try? c.decode(String.self, forKey: .title)) ?? ""
    subtitle = (try? c.decode(String.self, forKey: .subtitle)) ?? ""
    timeRange = (try? c.decode(String.self, forKey: .timeRange)) ?? ""
    room = try? c.decodeIfPresent(String.self, forKey: .room)
    teacher = try? c.decodeIfPresent(String.self, forKey: .teacher)
    label = try? c.decodeIfPresent(String.self, forKey: .label)
    trailing = try? c.decodeIfPresent(String.self, forKey: .trailing)
    metaIcons = try? c.decodeIfPresent([String].self, forKey: .metaIcons)
    metaTexts = try? c.decodeIfPresent([String].self, forKey: .metaTexts)
    progress = try? c.decodeIfPresent(Double.self, forKey: .progress)
    minutes = try? c.decodeIfPresent(Int.self, forKey: .minutes)
    week = try? c.decodeIfPresent(Int.self, forKey: .week)
    accent = (try? c.decodeIfPresent(Int.self, forKey: .accent)) ?? 0xFF1D6FD8
    at = try? c.decodeIfPresent(Double.self, forKey: .at)
    startsAt = try? c.decodeIfPresent(Double.self, forKey: .startsAt)
    endsAt = try? c.decodeIfPresent(Double.self, forKey: .endsAt)
  }

  /// The pill's label, falling back to the status wording for an older
  /// payload that has no `label`.
  var pillLabel: String {
    if let label, !label.isEmpty { return label }
    switch status {
    case .inClass: return "正在上课"
    case .upcoming: return "下一节"
    default: return statusLabel
    }
  }

  /// True when there is no course to draw.
  var isEmpty: Bool { title.isEmpty }

  /// The room, falling back to the combined line if the app sent no room.
  var roomLabel: String {
    if let room, !room.isEmpty { return room }
    return subtitle
  }

  /// The teacher alone, when known.
  var teacherLabel: String {
    if let teacher, !teacher.isEmpty { return teacher }
    return ""
  }

  /// "第 8 周".
  var weekLabel: String? { week.map { "第 \($0) 周" } }

  /// The leading label.
  var statusLabel: String {
    switch status {
    case .inClass: return "正在上课"
    case .upcoming: return "下一节课"
    case .free: return "今天没课"
    case .done: return "今日课程已结束"
    case .idle: return "课表待同步"
    }
  }

  /// The countdown at the top right: how long is left, or how long until it
  /// starts. Empty when there is nothing to count, so the time range never
  /// shows up twice.
  var timeHint: String {
    guard let minutes else { return "" }
    switch status {
    case .inClass: return "还有 \(minutes) 分钟"
    case .upcoming:
      if minutes < 60 { return "\(minutes) 分钟后" }
      if minutes < 24 * 60 { return "\(minutes / 60) 小时后" }
      return "\(minutes / (24 * 60)) 天后"
    default: return ""
    }
  }
}

/// Timestamped display states computed by Flutter, never school API data.
struct WidgetTimeline: Codable {
  var v: Int
  var expiresAt: Double
  var entries: [WidgetSnapshot]

  func snapshot(at date: Date) -> WidgetSnapshot? {
    let now = date.timeIntervalSince1970 * 1000
    guard v == 2, now < expiresAt,
          var value = entries.last(where: { ($0.at ?? .infinity) <= now }) else { return nil }
    if value.status == .inClass, let start = value.startsAt, let end = value.endsAt, end > start {
      value.progress = min(1, max(0, (now - start) / (end - start)))
      value.minutes = max(0, Int((end - now) / 60000))
    } else if value.status == .upcoming, let start = value.startsAt {
      value.minutes = max(0, Int((start - now) / 60000))
    }
    return value
  }
}

enum WidgetSnapshotStore {
  static let appGroup = "group.com.sayqz.xinliLite"
  static let key = "xinli.widget.snapshot"
  static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

  static func save(_ raw: String, group: String) {
    guard group == appGroup else { return }
    defaults?.set(raw, forKey: key)
    WidgetCenter.shared.reloadTimelines(ofKind: "ClassWidget")
  }

  static func clear(group: String?) {
    defaults?.removeObject(forKey: key)
    WidgetCenter.shared.reloadTimelines(ofKind: "ClassWidget")
  }

  static func loadTimeline() -> WidgetTimeline? {
    guard let raw = defaults?.string(forKey: key) else { return nil }
    return try? JSONDecoder().decode(WidgetTimeline.self, from: Data(raw.utf8))
  }

  static func load() -> WidgetSnapshot? { loadTimeline()?.snapshot(at: Date()) }
}
