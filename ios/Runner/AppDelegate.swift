import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var courseActivities: CourseActivityService?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if notification.request.content.userInfo["xinliRoute"] as? String == "schedule" {
      completionHandler([.banner, .list, .sound])
    } else {
      super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.notification.request.content.userInfo["xinliRoute"] as? String == "schedule" {
      Self.pendingRoute = "schedule"
      NotificationCenter.default.post(name: Notification.Name("XinliWidgetRoute"), object: nil)
      completionHandler()
    } else {
      super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerWidgetChannel(engineBridge.applicationRegistrar.messenger())
    courseActivities = CourseActivityService(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

// MARK: - Home-screen widget

extension AppDelegate {
  /// The tab a launch asked for, if any.
  static var pendingRoute: String?

  /// The widget bridge: the Flutter side sends the finished snapshot as JSON
  /// and this writes it into the App Group the widget extension reads.
  func registerWidgetChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "xinli_lite/widgets",
      binaryMessenger: messenger
    )
    NotificationCenter.default.addObserver(forName: Notification.Name("XinliWidgetRoute"), object: nil, queue: .main) { _ in
      channel.invokeMethod("routeAvailable", arguments: nil)
    }
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "sync":
        guard
          let args = call.arguments as? [String: Any],
          let raw = args["raw"] as? String
        else {
          result(FlutterError(code: "bad_args", message: "raw missing", details: nil))
          return
        }
        WidgetSnapshotStore.save(raw, group: args["group"] as? String ?? WidgetSnapshotStore.appGroup)
        result(nil)
      case "initialRoute":
        // A widget tap asks for the timetable; it is consumed the first
        // time the app asks, so the launcher afterwards starts normally.
        result(Self.pendingRoute)
        Self.pendingRoute = nil
      case "clear":
        let args = call.arguments as? [String: Any]
        WidgetSnapshotStore.clear(group: args?["group"] as? String)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
