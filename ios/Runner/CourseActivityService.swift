import ActivityKit
import Flutter
import UIKit

/// Local preview only. A future staleDate is NOT a scheduled end.
/// Do not enable unattended production requests until APNs end delivery,
/// pending-token registration and replenishment have been implemented/tested.
@MainActor
final class CourseActivityService {
  private var username: String?
  private var generation = 0
  private var cleanupTask: Task<Void, Never>?
  private var resumeObserver: NSObjectProtocol?
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "xinli_lite/course_activities", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor in
        guard let self else { result(nil); return }
        await self.handle(call, result: result)
      }
    }
    resumeObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        if #available(iOS 16.2, *) { await self?.removeExpired() }
      }
    }
  }

  private func fail(_ code: String, _ message: String, _ result: FlutterResult) {
    result(FlutterError(code: code, message: message, details: nil))
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) async {
    let args = call.arguments as? [String: Any] ?? [:]
    guard #available(iOS 16.2, *) else {
      if call.method == "session" || call.method == "status" { result(["testing": false]); return }
      fail("unsupported", "灵动岛测试需要 iOS 16.2 或更新版本", result)
      return
    }
    switch call.method {
    case "session":
      generation += 1
      username = args["username"] as? String
      // Includes pending activities, so logout cannot leave a later reminder.
      if username != "202303310112" { await stopAll() }
      await removeExpired()
      result(status())
    case "status":
      await removeExpired()
      result(status())
    case "stopTest":
      generation += 1
      await stopAll()
      result(status())
    case "startTest":
      guard username == "202303310112" else {
        fail("forbidden", "当前账号没有灵动岛测试权限", result); return
      }
      guard UIApplication.shared.applicationState == .active else {
        fail("foreground", "请在 App 前台开启测试", result); return
      }
      guard ActivityAuthorizationInfo().areActivitiesEnabled else {
        fail("disabled", "请在系统设置中允许新理Lite使用实时活动", result); return
      }
      generation += 1
      let revision = generation
      await stopAll()
      guard revision == generation, username == "202303310112" else {
        result(["testing": false]); return
      }
      let now = Date()
      // This exercises the actual scheduled API; no Dart timer starts it.
      let scheduled: Bool
      if #available(iOS 26.0, *) { scheduled = true } else { scheduled = false }
      let show = now.addingTimeInterval(scheduled ? 3 : 0)
      let starts = show.addingTimeInterval(60)
      let course = args["course"] as? [String: Any] ?? [:]
      let attributes = CourseActivityAttributes(
        occurrenceID: UUID().uuidString,
        title: String((course["title"] as? String ?? "课前提醒测试").prefix(80)),
        location: String((course["location"] as? String ?? "测试教室").prefix(80)),
        teacher: String((course["teacher"] as? String ?? "").prefix(40)),
        showAt: show, startsAt: starts, dismissAt: starts.addingTimeInterval(60), isTest: true
      )
      let content = ActivityContent(
        state: CourseActivityAttributes.ContentState(accent: args["accent"] as? Int ?? 0xFF1D6FD8),
        staleDate: starts
      )
      do {
        let activity: Activity<CourseActivityAttributes>
        if #available(iOS 26.0, *) {
          activity = try Activity.request(
            attributes: attributes, content: content, pushType: nil, style: .standard,
            alertConfiguration: AlertConfiguration(
              title: "课前提醒测试", body: "模拟课程将在 1 分钟后开始", sound: .default
            ), start: show
          )
        } else {
          activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        }
        armForegroundCleanup(activity)
        result(status())
      } catch {
        fail("request_failed", "系统未能创建实时活动，请检查实时活动权限或关闭其他活动后重试", result)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @available(iOS 16.2, *)
  private func status() -> [String: Any] {
    let activities = Activity<CourseActivityAttributes>.activities.filter {
      $0.activityState != .ended && $0.activityState != .dismissed && $0.attributes.isTest
    }
    let phase: String
    if let activity = activities.first {
      if #available(iOS 26.0, *), activity.activityState == .pending { phase = "pending" }
      else { phase = Date() >= activity.attributes.startsAt ? "started" : "upcoming" }
    } else { phase = "" }
    return ["testing": !activities.isEmpty, "phase": phase, "backgroundEndAvailable": false]
  }

  @available(iOS 16.2, *)
  private func stopAll() async {
    cleanupTask?.cancel()
    cleanupTask = nil
    for activity in Activity<CourseActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  @available(iOS 16.2, *)
  private func removeExpired() async {
    for activity in Activity<CourseActivityAttributes>.activities {
      if activity.attributes.dismissAt <= Date() || username != "202303310112" {
        await activity.end(nil, dismissalPolicy: .immediate)
      } else {
        armForegroundCleanup(activity)
      }
    }
  }

  @available(iOS 16.2, *)
  private func armForegroundCleanup(_ activity: Activity<CourseActivityAttributes>) {
    cleanupTask?.cancel()
    cleanupTask = Task { @MainActor in
      let delay = max(0, activity.attributes.dismissAt.timeIntervalSinceNow)
      do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
      catch { return }
      guard !Task.isCancelled else { return }
      // Best effort while the process runs. Suspension/force-quit needs APNs.
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }
}
