import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private let backgroundTaskChannel = "budget_ai/ios_background_task"
  private var backgroundTaskIdentifier = UIBackgroundTaskIdentifier.invalid

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    FlutterMethodChannel(
      name: backgroundTaskChannel,
      binaryMessenger: controller.binaryMessenger
    ).setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(false)
        return
      }

      switch call.method {
      case "start":
        result(self.startBackgroundTask())
      case "stop":
        self.stopBackgroundTask()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func startBackgroundTask() -> Bool {
    if backgroundTaskIdentifier != .invalid {
      return true
    }

    backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(
      withName: "Budget AI Chat Response"
    ) { [weak self] in
      self?.stopBackgroundTask()
    }

    return backgroundTaskIdentifier != .invalid
  }

  private func stopBackgroundTask() {
    guard backgroundTaskIdentifier != .invalid else {
      return
    }

    UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
    backgroundTaskIdentifier = .invalid
  }
}
