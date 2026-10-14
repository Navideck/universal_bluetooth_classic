import ExternalAccessory
import ObjectiveC
import UIKit

/// Workaround for `EAAccessoryManager.showBluetoothAccessoryPicker` being broken
/// under the `UIScene` lifecycle.
///
/// Apple's picker (`BTDevicePicker` in `CoreBluetoothUI`) decides how to present
/// itself from the app delegate's `window`:
///
/// * If the app delegate responds to `window` **and it is non-nil**, the picker
///   creates its own alert window and attaches its remote view controller to it.
/// * Otherwise it reuses an existing window but never attaches its remote view
///   controller, so nothing is shown.
///
/// Under the `UIScene` lifecycle UIKit assigns the window to the *scene* delegate,
/// leaving `AppDelegate.window` `nil`, so the picker never presents. Binding the
/// active scene's key window back to the app delegate fixes that on every
/// affected OS version we tested (iOS 16 and iOS 27). The binding is only needed
/// while the picker is presenting, so it is restored by `end(_:)`.
///
/// Before iOS 26.5 the picker's own alert window is created scene-less
/// (`UIWindow(frame:)`), which cannot be displayed on iOS 13+, so on those
/// versions we additionally swizzle `UIWindow.makeKeyAndVisible()` to attach the
/// active scene to any scene-less window being made key. Apple fixed this
/// natively in iOS 26.5, so the swizzle is skipped there.
///
/// All state is global, so the workaround tracks in-flight picker presentations
/// by token: only the last presentation to finish tears the global state down,
/// and a watchdog restores it if a presentation never reports completion.
enum EABluetoothAccessoryPickerWorkaround {
  /// `true` when the running OS still creates the picker window without a scene.
  private static let requiresSceneLessWindowFix: Bool =
    !ProcessInfo.processInfo.isOperatingSystemAtLeast(
      OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 0)
    )

  /// Upper bound on how long the global state may stay applied when the picker
  /// never invokes its completion handler. The picker makes its window key as
  /// soon as it is presented, so tearing the workaround down later is harmless;
  /// this only guards against a leaked swizzle/window binding.
  private static let teardownWatchdogInterval: TimeInterval = 60

  /// Identifiers of picker presentations currently in flight.
  private static var activeSessions: Set<Int> = []
  private static var nextSessionID = 0
  private static var didBindWindow = false
  private static var isSwizzled = false
  private static var teardownWatchdog: DispatchWorkItem?

  /// Prepare presentation just before calling the picker. Must be called on the
  /// main thread.
  /// - Returns: A token that must be passed back to `end(_:)` once the picker
  ///   finishes. `0` on OS versions that do not need the workaround.
  @discardableResult
  static func begin() -> Int {
    guard #available(iOS 13.0, *) else { return 0 }
    nextSessionID += 1
    let sessionID = nextSessionID
    if activeSessions.isEmpty {
      bindSceneWindowToAppDelegate()
      if requiresSceneLessWindowFix {
        installWindowSwizzle()
      }
      scheduleTeardownWatchdog()
    }
    activeSessions.insert(sessionID)
    return sessionID
  }

  /// Restore state once the picker has finished. Must be called on the main
  /// thread.
  /// - Parameter sessionID: The token returned by the matching `begin()` call.
  static func end(_ sessionID: Int) {
    guard #available(iOS 13.0, *) else { return }
    guard activeSessions.remove(sessionID) != nil, activeSessions.isEmpty else { return }
    teardown()
  }

  /// Undo every global side effect. Safe to call more than once.
  @available(iOS 13.0, *)
  private static func teardown() {
    teardownWatchdog?.cancel()
    teardownWatchdog = nil
    activeSessions.removeAll()
    removeWindowSwizzle()
    restoreAppDelegateWindow()
  }

  @available(iOS 13.0, *)
  private static func scheduleTeardownWatchdog() {
    teardownWatchdog?.cancel()
    let item = DispatchWorkItem { teardown() }
    teardownWatchdog = item
    DispatchQueue.main.asyncAfter(deadline: .now() + teardownWatchdogInterval, execute: item)
  }

  // MARK: Window binding
  @available(iOS 13.0, *)
  private static func bindSceneWindowToAppDelegate() {
    guard let appDelegate = UIApplication.shared.delegate as? NSObject,
          appDelegate.responds(to: NSSelectorFromString("window")),
          appDelegate.responds(to: NSSelectorFromString("setWindow:")),
          appDelegate.value(forKey: "window") as? UIWindow == nil,
          let window = activeSceneKeyWindow()
    else { return }
    appDelegate.setValue(window, forKey: "window")
    didBindWindow = true
  }

  /// Restores `AppDelegate.window` to the `nil` value it had before `begin()`.
  @available(iOS 13.0, *)
  private static func restoreAppDelegateWindow() {
    guard didBindWindow else { return }
    didBindWindow = false
    guard let appDelegate = UIApplication.shared.delegate as? NSObject else { return }
    appDelegate.setValue(nil, forKey: "window")
  }

  @available(iOS 13.0, *)
  private static func activeSceneKeyWindow() -> UIWindow? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    return scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
  }

  // MARK: Swizzle
  @available(iOS 13.0, *)
  private static func installWindowSwizzle() {
    guard !isSwizzled else { return }
    guard let original = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.makeKeyAndVisible)),
          let replacement = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.ea_makeKeyAndVisible))
    else { return }
    method_exchangeImplementations(original, replacement)
    isSwizzled = true
  }

  @available(iOS 13.0, *)
  private static func removeWindowSwizzle() {
    guard isSwizzled else { return }
    guard let original = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.makeKeyAndVisible)),
          let replacement = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.ea_makeKeyAndVisible))
    else { return }
    method_exchangeImplementations(original, replacement)
    isSwizzled = false
  }
}

@available(iOS 13.0, *)
private extension UIWindow {
  /// Attaches the active scene to a scene-less window before making it key, so
  /// the private accessory picker window can be displayed on iOS 13+.
  @objc func ea_makeKeyAndVisible() {
    if windowScene == nil {
      let scene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
      if let scene {
        windowScene = scene
      }
    }
    ea_makeKeyAndVisible()
  }
}
