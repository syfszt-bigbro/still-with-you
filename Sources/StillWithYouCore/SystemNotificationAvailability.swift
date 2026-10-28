import Foundation

/// UserNotifications requires a real application bundle. SwiftPM's raw
/// executable has no LaunchServices bundle proxy and calling
/// `UNUserNotificationCenter.current()` there raises an Objective-C exception
/// before Swift can catch it.
public enum SystemNotificationAvailability {
  public static func isAvailable(
    bundleURL: URL = Bundle.main.bundleURL,
    bundleIdentifier: String? = Bundle.main.bundleIdentifier
  ) -> Bool {
    bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
      && !(bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
  }
}
