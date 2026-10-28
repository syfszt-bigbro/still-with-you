import Foundation

public enum CompanionPromptPolicy {
  public static func reminder(timer: FocusTimer) -> Int? {
    guard !timer.paused, !timer.awaitingReflection, timer.remaining > 0 else { return nil }
    let thresholds = timer.duration >= 20 * 60 ? [8, 3] : timer.duration >= 6 * 60 ? [3] : timer.duration >= 3 * 60 ? [1] : []
    // A delayed tick may notify within 30 seconds, but never replays old reminders.
    return thresholds.first { !(timer.advanceReminderMinutes ?? []).contains($0) && timer.remaining <= Double($0 * 60) && timer.remaining > Double($0 * 60 - 30) }
  }
  public static func season(at date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    switch calendar.component(.month, from: date) {
    case 3...5: return "春天"
    case 6...8: return "夏天"
    case 9...11: return "秋天"
    default: return "冬天"
    }
  }
}
