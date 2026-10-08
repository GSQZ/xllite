import SwiftUI

#if os(iOS)
import ActivityKit
import WidgetKit

@available(iOSApplicationExtension 16.2, *)
struct CourseLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: CourseActivityAttributes.self) { context in
      CourseActivityCard(display: CourseActivityDisplay(context))
        .activityBackgroundTint(Color(.secondarySystemBackground))
        .activitySystemActionForegroundColor(.primary)
        .widgetURL(URL(string: "xinlilite://schedule"))
    } dynamicIsland: { context in
      let display = CourseActivityDisplay(context)
      return DynamicIsland {
        // One full-width region below the camera keeps every row on the
        // same inset; independent side regions have different system bounds.
        DynamicIslandExpandedRegion(.bottom) {
          CourseIslandExpandedContent(display: display)
            .padding(.horizontal, 16)
        }
      } compactLeading: {
        Image(systemName: "graduationcap.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(display.tint(onDark: true))
      } compactTrailing: {
        CourseCountdown(display: display)
          .font(.system(size: 13, weight: .semibold, design: .rounded))
          .foregroundStyle(display.tint(onDark: true))
          .frame(width: 46, alignment: .trailing)
      } minimal: {
        Image(systemName: "graduationcap.fill")
          .foregroundStyle(display.tint(onDark: true))
      }
      .widgetURL(URL(string: "xinlilite://schedule"))
      .keylineTint(display.tint(onDark: true))
      .contentMargins(.all, 16, for: .expanded)
    }
  }
}

@available(iOSApplicationExtension 16.2, *)
extension CourseActivityDisplay {
  init(_ context: ActivityViewContext<CourseActivityAttributes>) {
    let attributes = context.attributes
    self.init(title: attributes.title, location: attributes.location,
              showAt: attributes.showAt, startsAt: attributes.startsAt,
              isTest: attributes.isTest, isStale: context.isStale,
              accent: context.state.accent)
  }
}
#endif

/// The same SwiftUI components are used in the extension and native visual QA.
/// Classroom and start time take priority over teacher names in the island.
struct CourseActivityDisplay {
  var title: String
  var location: String
  var showAt: Date
  var startsAt: Date
  var isTest: Bool
  var isStale: Bool
  var accent: Int

  var startLabel: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: startsAt)
  }

  func tint(onDark: Bool) -> Color {
    // The island is always black, including when the phone uses light mode.
    // Lift dark skins so the countdown stays legible without changing hue.
    let lift = onDark ? 0.32 : 0.0
    func component(_ shift: Int) -> Double {
      let value = Double((accent >> shift) & 255) / 255
      return value + (1 - value) * lift
    }
    return Color(.sRGB, red: component(16), green: component(8), blue: component(0), opacity: 1)
  }
}

@available(iOS 16.2, macOS 13.0, *)
struct CourseActivityStatus: View {
  let display: CourseActivityDisplay
  var onIsland = false
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    HStack(spacing: 6) {
      Circle().fill(display.tint(onDark: onIsland || colorScheme == .dark))
        .frame(width: 5, height: 5)
      Text(display.isStale ? "已开始上课" : (display.isTest && onIsland ? "课前测试" : "即将上课"))
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(display.tint(onDark: onIsland || colorScheme == .dark))
      if display.isTest && !onIsland {
        Text("测试")
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 5).padding(.vertical, 2)
          .background(.primary.opacity(0.09), in: Capsule())
      }
    }
    .lineLimit(1)
    .fixedSize(horizontal: true, vertical: false)
    .frame(minHeight: 24, alignment: .center)
  }
}

@available(iOS 16.2, macOS 13.0, *)
struct CourseCountdown: View {
  let display: CourseActivityDisplay
  var body: some View {
    Group {
      if display.isStale {
        Text("已上课")
      } else {
        // Leave pauseTime nil: passing the interval end pauses at the initial duration.
        // Timer Text takes all proposed width. Align its TEXT explicitly;
        // aligning only its outer frame leaves the digits floating mid-island.
        Text(timerInterval: display.showAt...display.startsAt,
             countsDown: true, showsHours: false)
      }
    }
    .monospacedDigit()
    .multilineTextAlignment(.trailing)
    .lineLimit(1)
    .minimumScaleFactor(0.85)
    .accessibilityLabel(display.isStale ? "已上课" : "距离上课")
  }
}

@available(iOS 16.2, macOS 13.0, *)
struct CourseActivityDetails: View {
  let display: CourseActivityDisplay

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text(display.title)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(.primary)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Image(systemName: "mappin.and.ellipse")
            .font(.system(size: 10, weight: .medium))
          Text(display.location.isEmpty ? "教室待定" : display.location)
            .font(.system(size: 12))
            .lineLimit(1).truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Text("\(display.startLabel) 上课")
          .font(.system(size: 12)).monospacedDigit()
          .fixedSize(horizontal: true, vertical: false)
      }
      .foregroundStyle(.secondary)
    }
  }
}

@available(iOS 16.2, macOS 13.0, *)
struct CourseIslandExpandedContent: View {
  let display: CourseActivityDisplay
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        CourseActivityStatus(display: display, onIsland: true)
        Spacer(minLength: 16)
        CourseCountdown(display: display)
          .font(.system(size: 20, weight: .semibold, design: .rounded))
          .foregroundStyle(display.tint(onDark: true))
          .frame(width: 72, alignment: .trailing)
      }
      CourseActivityDetails(display: display)
    }
  }
}

@available(iOS 16.2, macOS 13.0, *)
struct CourseActivityCard: View {
  let display: CourseActivityDisplay
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center) {
        CourseActivityStatus(display: display)
        Spacer(minLength: 12)
        CourseCountdown(display: display)
          .font(.system(size: 22, weight: .semibold, design: .rounded))
          .foregroundStyle(display.tint(onDark: colorScheme == .dark))
          .frame(width: 78, alignment: .trailing)
      }
      CourseActivityDetails(display: display)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }
}
