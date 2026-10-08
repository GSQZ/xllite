import SwiftUI
import WidgetKit

/// One moment on the widget's timeline: the snapshot plus when it was taken.
struct ClassEntry: TimelineEntry {
  let date: Date
  let snapshot: WidgetSnapshot?
}

/// The widget's data source. The app pushes snapshots, so this only has to
/// decide when the next redraw is needed: at the next class boundary, or in
/// fifteen minutes if that is sooner.
struct ClassTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> ClassEntry {
    ClassEntry(date: Date(), snapshot: .placeholder)
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (ClassEntry) -> Void
  ) {
    completion(ClassEntry(date: Date(), snapshot: WidgetSnapshotStore.load() ?? .placeholder))
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<ClassEntry>) -> Void
  ) {
    let now = Date()
    let data = WidgetSnapshotStore.loadTimeline()
    let horizon = now.addingTimeInterval(6 * 60 * 60)
    var dates = Set<Date>([now, horizon])
    let firstMinute = floor(now.timeIntervalSince1970 / 60) * 60 + 60
    for seconds in stride(from: firstMinute, through: horizon.timeIntervalSince1970, by: 60) {
      dates.insert(Date(timeIntervalSince1970: seconds))
    }
    // Include exact class/midnight boundaries and expiry even if WidgetKit
    // delays its next reload. Each snapshot is already calculated by Flutter.
    for entry in data?.entries ?? [] {
      if let at = entry.at {
        let date = Date(timeIntervalSince1970: at / 1000)
        if date > now { dates.insert(date) }
      }
    }
    if let expiry = data?.expiresAt {
      let date = Date(timeIntervalSince1970: expiry / 1000)
      if date > now { dates.insert(date) }
    }
    let entries = dates.sorted().map { ClassEntry(date: $0, snapshot: data?.snapshot(at: $0)) }
    completion(Timeline(entries: entries, policy: .after(horizon)))
  }
}

@main
struct ClassWidgetBundle: WidgetBundle {
  var body: some Widget {
    ClassWidget()
    if #available(iOSApplicationExtension 16.2, *) {
      CourseLiveActivity()
    }
  }
}

struct ClassWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: "ClassWidget",
      provider: ClassTimelineProvider()
    ) { entry in
      ClassWidgetView(snapshot: entry.snapshot)
    }
    .configurationDisplayName("新理课表")
    .description("显示正在上的课和下一节课。")
    .supportedFamilies([.systemMedium])
  }
}

/// The widget itself: the home screen's course card, shrunk to a widget.
/// Same language — a pill saying what this is, a big title, and a meta row
/// of icon + value pairs — on the card's own quiet surface.
struct ClassWidgetView: View {
  let snapshot: WidgetSnapshot?

  private var accent: Color { Color(hex: snapshot?.accent ?? 0xFF1D6FD8) }

  var body: some View {
    content
      .padding(.horizontal, 16)
      .padding(.vertical, 15)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .containerBackgroundCompat()
      .widgetURL(URL(string: "xinlilite://schedule"))
  }

  @ViewBuilder
  private var content: some View {
    if let snapshot, !snapshot.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        header(snapshot)

        Text(snapshot.title)
          .font(.system(size: 21, weight: .bold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .padding(.top, 10)

        meta(snapshot)
          .padding(.top, 9)

        // The room owns the last line: it is the one value that decides
        // whether a student finds the classroom, so nothing shares its row
        // and it is never truncated.
        if !snapshot.roomLabel.isEmpty {
          HStack(spacing: 5) {
            Image(systemName: "mappin.and.ellipse")
              .font(.system(size: 11.5))
              .foregroundStyle(.secondary)
            Text(snapshot.roomLabel)
              .font(.system(size: 13))
              .foregroundStyle(.secondary)
              .lineLimit(2)
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
          }
          .padding(.top, 7)
        }

        if let progress = snapshot.progress {
          ProgressBar(progress: progress, tint: accent)
            .padding(.top, 10)
        }
      }
    } else {
      VStack(alignment: .leading, spacing: 5) {
        Text(emptyTitle)
          .font(.system(size: 18, weight: .bold))
          .lineLimit(1)
        Text(emptyHint)
          .font(.system(size: 12.5))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }

  /// The pill on the left, the countdown on the right — the home card's
  /// first row, and the reason the room no longer gets squeezed.
  @ViewBuilder
  private func header(_ snapshot: WidgetSnapshot) -> some View {
    HStack(spacing: 8) {
      HStack(spacing: 6) {
        Circle()
          .fill(accent)
          .frame(width: 6, height: 6)
        Text(snapshot.pillLabel)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(accent)
          .lineLimit(1)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        Capsule().fill(accent.opacity(0.14))
      )

      Spacer(minLength: 8)

      if let trailing = snapshot.trailing, !trailing.isEmpty {
        Text(trailing)
          .font(.system(size: 12.5, weight: .semibold))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }

  /// Time and teacher, each with its own glyph — the home card's meta row.
  /// The room is not here; it draws on its own line below.
  @ViewBuilder
  private func meta(_ snapshot: WidgetSnapshot) -> some View {
    let icons = snapshot.metaIcons ?? []
    let texts = snapshot.metaTexts ?? []
    HStack(spacing: 12) {
      ForEach(Array(texts.enumerated()), id: \.offset) { index, text in
        HStack(spacing: 4) {
          Image(systemName: symbol(for: index < icons.count ? icons[index] : ""))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize()
          Text(text)
            .font(.system(size: 12.5))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
        }
      }
      Spacer(minLength: 0)
    }
  }

  private func symbol(for key: String) -> String {
    switch key {
    case "person": return "person"
    default: return "clock"
    }
  }

  private var emptyTitle: String {
    switch snapshot?.status {
    case .done: return "今天的课都上完啦"
    case .free: return "今天没有课程"
    default: return "课表还没同步"
    }
  }

  private var emptyHint: String {
    switch snapshot?.status {
    case .done, .free: return "好好享受课余时光"
    default: return "打开新理Lite 看一眼课表"
    }
  }
}

/// Slim progress track for the class in progress.
private struct ProgressBar: View {
  let progress: Double
  let tint: Color

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(tint.opacity(0.16))
        Capsule()
          .fill(tint)
          .frame(width: max(6, geo.size.width * min(max(progress, 0), 1)))
      }
    }
    .frame(height: 4)
  }
}


private extension View {
  /// iOS 17 wants an explicit container background; earlier versions paint
  /// the widget's own background instead.
  @ViewBuilder
  func containerBackgroundCompat() -> some View {
    if #available(iOS 17.0, *) {
      containerBackground(.fill.tertiary, for: .widget)
    } else {
      background(Color(.systemBackground))
    }
  }
}

private extension Color {
  init(hex: Int) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: 1
    )
  }
}

extension WidgetSnapshot {
  /// What the widget gallery shows before the app has ever synced.
  static let placeholder = WidgetSnapshot(
    status: .upcoming,
    title: "高等数学",
    subtitle: "实验楼A305 · 王老师",
    timeRange: "08:00 - 09:40",
    progress: nil,
    minutes: 23,
    week: 8,
    accent: 0xFF1D6FD8
  )
}
