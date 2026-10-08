import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    capture(connectionOptions.urlContexts)
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    capture(URLContexts)
    super.scene(scene, openURLContexts: URLContexts)
  }

  private func capture(_ contexts: Set<UIOpenURLContext>) {
    if contexts.contains(where: { $0.url.scheme == "xinlilite" && $0.url.host == "schedule" }) {
      AppDelegate.pendingRoute = "schedule"
      NotificationCenter.default.post(name: Notification.Name("XinliWidgetRoute"), object: nil)
    }
  }
}
