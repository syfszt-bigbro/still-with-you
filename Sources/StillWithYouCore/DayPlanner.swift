import Foundation

public enum DayPlanner {
  /// Keep the evening editable; 18:00 is a default, not the end of the day.
  public static func remainingDayRange(day: Date, now: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
    let midnight = calendar.dateInterval(of: .day, for: day)!.end
    let fourteen = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: day)!
    let eighteen = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day)!
    var start = fourteen
    if calendar.isDate(day, inSameDayAs: now) {
      start = max(fourteen, roundedHour(now, calendar: calendar))
      if start >= midnight {
        start = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 60).rounded(.up) * 60)
      }
    }
    return (start, start < eighteen ? eighteen : midnight)
  }
  public static func needsStartReminder(_ task: PlanTask, now: Date, activeTaskID: UUID?) -> Bool {
    guard task.deletedAt == nil, !task.isExpired(at: now, activeTaskID: activeTaskID), !task.cancelled, task.focus.outcome == .pending, task.focus.startedAt == nil,
      task.id != activeTaskID, task.startReminderDismissed != true,
      task.day == Day.key(now), let planned = task.plannedStart else { return false }
    return (task.nextStartReminderAt ?? planned) <= now
  }
  public static func canSchedule(start: Date, now: Date = Date()) -> Bool { start >= now }
  /// An exact hour stays unchanged; otherwise round forward, never back.
  public static func roundedHour(_ date: Date, calendar: Calendar = .current) -> Date {
    let hour = calendar.dateInterval(of: .hour, for: date)!.start
    return date == hour ? hour : calendar.date(byAdding: .hour, value: 1, to: hour)!
  }
  public static func slots(start: Date, end: Date, focus: Int = 45, activity: Int = 15) -> [Date] {
    guard [15, 30, 45].contains(focus), (0...15).contains(activity), end > start else { return [] }
    let duration = Double(focus + activity) * 60
    var cursor = start
    var output: [Date] = []
    while cursor.addingTimeInterval(duration) <= end && output.count < 48 {
      output.append(cursor)
      cursor = cursor.addingTimeInterval(duration)
    }
    return output
  }
}

/// Pause delays only the later, unstarted plans selected when this pause begins.
public enum PauseSchedule {
  public static func advance(tasks: inout [PlanTask], timer: inout FocusTimer, now: Date) {
    guard timer.paused, !timer.awaitingReflection else { return }
    if timer.pauseShiftedAt == nil {
      timer.pauseShiftedAt = now
      if let current = tasks.first(where: { $0.id == timer.taskID }), let start = current.plannedStart {
        timer.delayedTaskIDs = Array(Set((timer.delayedTaskIDs ?? []) + tasks.filter { $0.day == current.day && ($0.plannedStart ?? .distantPast) > start && !$0.cancelled && $0.deletedAt == nil && $0.focus.outcome == .pending && $0.focus.startedAt == nil }.map(\.id)))
      } else { timer.delayedTaskIDs = [] }
      return
    }
    let delta = now.timeIntervalSince(timer.pauseShiftedAt!)
    guard delta > 0 else { return }
    let ids = Set(timer.delayedTaskIDs ?? [])
    for i in tasks.indices where ids.contains(tasks[i].id) {
      guard !tasks[i].cancelled, tasks[i].deletedAt == nil, tasks[i].focus.outcome == .pending, tasks[i].focus.startedAt == nil, let start = tasks[i].plannedStart else { continue }
      let shifted = start.addingTimeInterval(delta)
      tasks[i].plannedStart = shifted
      tasks[i].day = Day.key(shifted)
      if let reminder = tasks[i].nextStartReminderAt { tasks[i].nextStartReminderAt = reminder.addingTimeInterval(delta) }
    }
    timer.pauseShiftedAt = now
  }
}
