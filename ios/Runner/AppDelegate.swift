import Flutter
import UIKit
import UserNotifications

private let financeChangedNotification =
  "com.muzamil.budget.ai.financeEntriesChanged" as CFString

private let handleFinanceChangedNotification: CFNotificationCallback = {
  _, observer, _, _, _ in
  guard let observer else { return }
  let delegate = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
  DispatchQueue.main.async {
    delegate.notifyFlutterFinanceChanged()
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var siriFinanceChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    siriFinanceChannel = FlutterMethodChannel(
      name: "budget_ai/siri_finance",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(self).toOpaque(),
      handleFinanceChangedNotification,
      financeChangedNotification,
      nil,
      .deliverImmediately
    )
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    notifyFlutterFinanceChanged()
  }

  fileprivate func notifyFlutterFinanceChanged() {
    siriFinanceChannel?.invokeMethod("financeEntriesChanged", arguments: nil)
  }

  deinit {
    CFNotificationCenterRemoveObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(self).toOpaque(),
      CFNotificationName(financeChangedNotification),
      nil
    )
  }
}
