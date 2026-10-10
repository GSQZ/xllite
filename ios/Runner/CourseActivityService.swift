import ActivityKit
import Flutter
import UIKit
import UserNotifications

/// User-selected native scheduling. No background timer is used to START an
/// activity. Without APNs, ending remains best effort while the app executes.
@MainActor
final class CourseActivityService {
  private let center = UNUserNotificationCenter.current()
  private let defaults = UserDefaults.standard
  private let channel: FlutterMethodChannel
  private var scope: String?
  private var enabled = false
  private var liveActivities = false
  private var accent = 0xFF1D6FD8
  private var courses: [NativeCourseReminder] = []
  private var warning: String?
  private var lastSyncedAt: Date?
  private var requestedLive = Set<String>()
  private var cleanupTasks: [String: Task<Void, Never>] = [:]
  private var resumeObserver: NSObjectProtocol?
  private var operations: Task<Void, Never>?
  private let prefix = "xinli.course."
  private let storeKey = "xinli.course.schedule.v1"

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "xinli_lite/course_activities", binaryMessenger: messenger)
    // Keep persisted production activities while Flutter restores authentication.
    scope = defaults.dictionary(forKey: storeKey)?["scope"] as? String
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor in
        guard let self else { result(nil); return }
        self.enqueue { await self.handle(call, result: result) }
      }
    }
    resumeObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        self.enqueue { await self.removeExpired() }
      }
    }
  }

  /// Serialize native reconciliation as well as Flutter calls. A logout cannot
  /// race an awaited notification add and leave another account's request behind.
  private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
    let previous = operations
    operations = Task { @MainActor in
      await previous?.value
      await operation()
    }
  }

  private func fail(_ code: String, _ message: String, _ result: FlutterResult) {
    result(FlutterError(code: code, message: message, details: nil))
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) async {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "session":
      let account = args["username"] as? String
      let origin = args["origin"] as? String ?? "https://xllite.sayqz.com"
      let nextScope = account.map { NativeCourseReminder.digest(origin + "\n" + $0) }
      let savedScope = defaults.dictionary(forKey: storeKey)?["scope"] as? String
      if nextScope != savedScope || nextScope == nil { await clearAll() }
      scope = nextScope
      if let nextScope {
        let settings = defaults.dictionary(forKey: "xinli.course.preferences." + nextScope) ?? [:]
        enabled = settings["enabled"] as? Bool ?? false
        liveActivities = settings["liveActivities"] as? Bool ?? false
        restorePlan()
        await reconcile()
      } else {
        enabled = false; liveActivities = false; courses = []; lastSyncedAt = nil
        requestedLive = []
      }
      result(await status())
    case "status":
      await reconcile()
      result(await status())
    case "sync":
      guard scope != nil else { fail("signed_out", "请先登录再安排提醒", result); return }
      guard let raw = args["courses"] as? [[String: Any]], raw.count <= 128 else {
        fail("bad_plan", "课表提醒数据不完整，请刷新课表", result); return
      }
      let parsed = raw.compactMap(NativeCourseReminder.init(json:))
      guard parsed.count == raw.count else {
        fail("bad_plan", "课程时间不完整，请刷新课表后重试", result); return
      }
      courses = NativeCourseReminder.upcoming(parsed, now: Date())
      accent = args["accent"] as? Int ?? accent
      lastSyncedAt = Date()
      savePlan()
      await reconcile()
      result(await status())
    case "configure":
      guard let scope else { fail("signed_out", "请先登录再设置提醒", result); return }
      guard UIApplication.shared.applicationState == .active else {
        fail("foreground", "请在 App 前台设置提醒", result); return
      }
      if args["requestPermission"] as? Bool == true {
        do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
        catch { fail("permission", "系统未能完成通知授权，请重试", result); return }
      }
      enabled = args["enabled"] as? Bool ?? enabled
      liveActivities = args["liveActivities"] as? Bool ?? liveActivities
      defaults.set(["enabled": enabled, "liveActivities": liveActivities],
                   forKey: "xinli.course.preferences." + scope)
      await reconcile()
      result(await status())
    case "openSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        result(await UIApplication.shared.open(url))
      } else { result(false) }
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func savePlan() {
    guard let scope, let data = try? JSONEncoder().encode(courses) else { return }
    defaults.set(["scope": scope, "courses": data, "accent": accent,
                  "syncedAt": lastSyncedAt?.timeIntervalSince1970 ?? 0,
                  "requestedLive": Array(requestedLive)], forKey: storeKey)
  }

  private func restorePlan() {
    guard let saved = defaults.dictionary(forKey: storeKey),
          saved["scope"] as? String == scope,
          let data = saved["courses"] as? Data,
          let parsed = try? JSONDecoder().decode([NativeCourseReminder].self, from: data) else {
      courses = []; lastSyncedAt = nil; requestedLive = []; return
    }
    courses = NativeCourseReminder.upcoming(parsed, now: Date())
    accent = saved["accent"] as? Int ?? accent
    requestedLive = Set(saved["requestedLive"] as? [String] ?? [])
    if let stamp = saved["syncedAt"] as? Double, stamp > 0 {
      lastSyncedAt = Date(timeIntervalSince1970: stamp)
    }
  }

  private func permission() async -> String {
    switch await center.notificationSettings().authorizationStatus {
    case .authorized: return "authorized"
    case .provisional: return "provisional"
    case .ephemeral: return "ephemeral"
    case .denied: return "denied"
    case .notDetermined: return "notDetermined"
    @unknown default: return "denied"
    }
  }

  private func status() async -> [String: Any] {
    let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }
    var liveCount = 0
    var activitiesAllowed = false
    var scheduledSupported = false
    if #available(iOS 26.0, *) { scheduledSupported = true }
    if #available(iOS 16.2, *) {
      activitiesAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
      for activity in Activity<CourseActivityAttributes>.activities where isRunning(activity) {
        if !activity.attributes.isTest && activity.attributes.accountScope == scope { liveCount += 1 }
      }
    }
    var values: [String: Any] = [
      "enabled": enabled,
      "liveActivities": liveActivities, "scheduledSupported": scheduledSupported,
      "activitiesAllowed": activitiesAllowed, "notificationPermission": await permission(),
      "scheduledCount": pending.count + liveCount, "liveCount": liveCount,
      "backgroundEndAvailable": false
    ]
    if let warning { values["warning"] = warning }
    if let lastSyncedAt { values["lastSyncedAt"] = lastSyncedAt.timeIntervalSince1970 * 1000 }
    // Coverage means the last real scheduled request, not the plan's horizon.
    let notificationIDs = Set(pending.map(\.identifier))
    var actualIDs = notificationIDs
    if #available(iOS 16.2, *) {
      for activity in Activity<CourseActivityAttributes>.activities where isRunning(activity) && !activity.attributes.isTest {
        actualIDs.insert(activity.attributes.occurrenceID)
      }
    }
    if let scope, let last = courses.last(where: { actualIDs.contains($0.identifier(scope: scope)) }) {
      values["scheduledUntil"] = last.startsAt.timeIntervalSince1970 * 1000
    }
    return values
  }

  private func clearNotifications(_ identifiers: [String]) {
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
    center.removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  private func clearAll() async {
    let pending = await center.pendingNotificationRequests()
    let delivered = await center.deliveredNotifications()
    clearNotifications(pending.map(\.identifier).filter { $0.hasPrefix(prefix) } +
                       delivered.map { $0.request.identifier }.filter { $0.hasPrefix(prefix) })
    if #available(iOS 16.2, *) {
      for activity in Activity<CourseActivityAttributes>.activities {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }
    for task in cleanupTasks.values { task.cancel() }
    cleanupTasks.removeAll()
    defaults.removeObject(forKey: storeKey)
    requestedLive = []
  }

  @available(iOS 16.2, *)
  private func isRunning(_ activity: Activity<CourseActivityAttributes>) -> Bool {
    activity.activityState != .ended && activity.activityState != .dismissed
  }

  private func removeExpired() async {
    if #available(iOS 16.2, *) {
      for activity in Activity<CourseActivityAttributes>.activities {
        let wrongAccount = activity.attributes.isTest || activity.attributes.accountScope != scope
        if wrongAccount || activity.attributes.dismissAt <= Date() || !isRunning(activity) {
          await activity.end(nil, dismissalPolicy: .immediate)
          cleanupTasks.removeValue(forKey: activity.id)?.cancel()
        } else { armCleanup(activity) }
      }
    }
  }

  private func reconcile() async {
    warning = nil
    await removeExpired()
    guard let scope else { return }
    let now = Date()
    courses = NativeCourseReminder.upcoming(courses, now: now)
    let desired = enabled ? courses : []
    let desiredIDs = Set(desired.map { $0.identifier(scope: scope) })
    requestedLive.formIntersection(Set(courses.map { $0.identifier(scope: scope) }))
    let delivered = await center.deliveredNotifications()
    let deliveredIDs = Set(delivered.map { $0.request.identifier })
    var liveIDs = Set<String>()
    let permission = await permission()
    let notificationsAllowed = ["authorized", "provisional", "ephemeral"].contains(permission)

    if #available(iOS 16.2, *) {
      let canSchedule: Bool
      if #available(iOS 26.0, *) { canSchedule = true } else { canSchedule = false }
      // Keep only two nearby activities. The system's quota is shared with
      // other apps; every request failure falls back for that course alone.
      let liveCandidates = liveActivities && canSchedule && ActivityAuthorizationInfo().areActivitiesEnabled
        ? Array(desired.filter { $0.startsAt > now }.prefix(2)) : []
      let liveDesired = Set(liveCandidates.map { $0.identifier(scope: scope) })
      for activity in Activity<CourseActivityAttributes>.activities where isRunning(activity) {
        if activity.attributes.isTest { continue }
        let id = activity.attributes.occurrenceID
        // A course already on the island remains until its dismissal boundary.
        let retained = desiredIDs.contains(id) && liveActivities && ActivityAuthorizationInfo().areActivitiesEnabled &&
          (liveDesired.contains(id) || activity.attributes.startsAt <= now)
        if !retained || activity.attributes.accountScope != scope {
          await activity.end(nil, dismissalPolicy: .immediate)
          cleanupTasks.removeValue(forKey: activity.id)?.cancel()
          requestedLive.remove(id)
        } else {
          liveIDs.insert(id)
          if activity.content.state.accent != accent {
            await activity.update(ActivityContent(state: .init(accent: accent), staleDate: activity.attributes.startsAt))
          }
          armCleanup(activity)
        }
      }
      if UIApplication.shared.applicationState == .active {
        for course in liveCandidates {
          let id = course.identifier(scope: scope)
          // Do not resurrect a user-dismissed activity or alert again after
          // this course's ordinary notification has already been delivered.
          if liveIDs.count >= 2 || liveIDs.contains(id) || requestedLive.contains(id) || deliveredIDs.contains(id) { continue }
          do {
            if #available(iOS 26.0, *) {
              // The two system subsystems have no shared transaction. Remove
              // the fallback before creating its replacement; on failure the
              // notification reconciliation below restores it.
              clearNotifications([id])
              let attributes = CourseActivityAttributes(
                occurrenceID: id, title: course.title, location: course.location, teacher: course.teacher,
                showAt: course.showAt, startsAt: course.startsAt, dismissAt: course.dismissAt,
                isTest: false, accountScope: scope
              )
              let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: .init(accent: accent), staleDate: course.startsAt),
                pushType: nil, style: .standard,
                alertConfiguration: AlertConfiguration(title: "课前提醒", body: "即将上课：\(course.title)", sound: .default),
                start: max(course.showAt, Date().addingTimeInterval(1))
              )
              liveIDs.insert(id)
              requestedLive.insert(id)
              savePlan()
              armCleanup(activity)
            }
          } catch {
            warning = "部分课程无法预约灵动岛，已尝试改用普通通知"
          }
        }
      }
      if liveActivities && !canSchedule { warning = "此系统支持普通课前通知，自动灵动岛需要 iOS 26 或更新版本" }
      else if liveActivities && !ActivityAuthorizationInfo().areActivitiesEnabled {
        warning = "实时活动未获允许，已尝试改用普通通知"
      }
    }

    let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }
    var liveEnabled = false
    if #available(iOS 26.0, *) {
      liveEnabled = liveActivities && ActivityAuthorizationInfo().areActivitiesEnabled
    }
    let notificationCourses = notificationsAllowed ? desired.filter {
      $0.showAt > now && !liveIDs.contains($0.identifier(scope: scope)) &&
        !(liveEnabled && requestedLive.contains($0.identifier(scope: scope)))
    } : []
    let notificationIDs = Set(notificationCourses.map { $0.identifier(scope: scope) })
    clearNotifications(pending.map(\.identifier).filter { !notificationIDs.contains($0) })
    // Deleted/changed courses must also disappear from Notification Center.
    clearNotifications(delivered.map { $0.request.identifier }.filter {
      $0.hasPrefix(prefix) && !desiredIDs.contains($0)
    })
    let existing = Set(pending.map(\.identifier))
    for course in notificationCourses {
      let id = course.identifier(scope: scope)
      if existing.contains(id) { continue }
      let content = UNMutableNotificationContent()
      content.title = "15 分钟后上课 · \(course.title)"
      let formatter = DateFormatter()
      formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
      formatter.dateFormat = "HH:mm"
      content.body = "\(formatter.string(from: course.startsAt)) 上课 · \(course.location.isEmpty ? "教室待定" : course.location)"
      content.sound = .default
      content.threadIdentifier = "xinli.course"
      content.userInfo = ["xinliRoute": "schedule"]
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, course.showAt.timeIntervalSinceNow), repeats: false)
      do { try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) }
      catch { warning = "部分课前通知未能安排，请重新同步" }
    }
    if enabled && !notificationsAllowed {
      warning = liveIDs.isEmpty ? "通知未获允许，请在系统设置中开启课前通知" : "普通通知未获允许，灵动岛以外的课程暂时无法提醒"
    }
    savePlan()
  }

  @available(iOS 16.2, *)
  private func armCleanup(_ activity: Activity<CourseActivityAttributes>) {
    guard cleanupTasks[activity.id] == nil else { return }
    cleanupTasks[activity.id] = Task { @MainActor in
      let delay = max(0, activity.attributes.dismissAt.timeIntervalSinceNow)
      do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
      catch { return }
      guard !Task.isCancelled else { return }
      // Suspension/force-quit is NOT solved by this task. APNs is needed there.
      await activity.end(nil, dismissalPolicy: .immediate)
      cleanupTasks.removeValue(forKey: activity.id)
    }
  }
}
