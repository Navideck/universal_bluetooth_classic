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
/// affected OS version we tested (iOS 16 and iOS 27).
///
/// Before iOS 26.5 the picker's own alert window is created scene-less
/// (`UIWindow(frame:)`), which cannot be displayed on iOS 13+, so on those
/// versions we additionally swizzle `UIWindow.makeKeyAndVisible()` to attach the
/// active scene to any scene-less window being made key. Apple fixed this
/// natively in iOS 26.5, so the swizzle is skipped there.
enum EABluetoothAccessoryPickerWorkaround {
  /// `true` when the running OS still creates the picker window without a scene.
  private static let requiresSceneLessWindowFix: Bool =
    !ProcessInfo.processInfo.isOperatingSystemAtLeast(
      OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 0)
    )

  private static var isSwizzled = false

  /// Prepare presentation just before calling the picker. Must be called on the main thread.
  static func begin() {
    guard #available(iOS 13.0, *) else { return }
    bindSceneWindowToAppDelegate()
    if requiresSceneLessWindowFix {
      installWindowSwizzle()
    }
  }

  /// Restore state once the picker has finished.
  static func end() {
    guard #available(iOS 13.0, *) else { return }
    removeWindowSwizzle()
  }

  // MARK: Window binding
  @available(iOS 13.0, *)
  private static func bindSceneWindowToAppDelegate() {
    guard let appDelegate = UIApplication.shared.delegate as? NSObject,
          appDelegate.responds(to: NSSelectorFromString("window")),
          appDelegate.value(forKey: "window") as? UIWindow == nil,
          let window = activeSceneKeyWindow()
    else { return }
    appDelegate.setValue(window, forKey: "window")
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
