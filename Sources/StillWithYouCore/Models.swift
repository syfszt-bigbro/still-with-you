import Foundation

public enum Outcome: String, Codable, CaseIterable, Sendable {
  case pending, done, partial, skipped
  public var title: String {
    switch self {
    case .pending: return "未记录"
    case .done: return "完成"
    case .partial: return "部分完成"
    case .skipped: return "未完成"
    }
  }
}
public enum Phase: String, Codable, Sendable {
  case focus, exercise
  public var title: String { self == .focus ? "专注" : "运动" }
}
public struct Reflection: Codable, Equatable, Sendable {
  public var outcome: Outcome = .pending
  public var note = ""
  public var score: Int?
  public var seconds: Double = 0
  public var recordedAt: Date?
  public var startedAt: Date?
  public var endedAt: Date?
  public var updatedAt: Date?
  public init(
    outcome: Outcome = .pending, note: String = "", score: Int? = nil, seconds: Double = 0,
    recordedAt: Date? = nil
  ) {
    self.outcome = outcome
    self.note = note
    self.score = score.map { min(10, max(0, $0)) }
    self.seconds = max(0, seconds)
    self.recordedAt = recordedAt
  }
}
public struct PlanTask: Codable, Identifiable, Sendable {
  public var id = UUID()
  public var day: String
  public var title: String
  public var focusMinutes: Int
  public var exerciseMinutes: Int
  public var exercise: String
  public var focus = Reflection()
  public var movement = Reflection()
  public var cancelled = false
  public var deletedAt: Date?
  public var expiryReason: String?
  public var expiryReasonUpdatedAt: Date?
  public func isExpired(at now: Date = Date(), activeTaskID: UUID? = nil) -> Bool {
    guard !cancelled, deletedAt == nil, id != activeTaskID, focus.outcome == .pending, focus.startedAt == nil, movement.startedAt == nil, movement.outcome == .pending, let start = plannedStart else { return false }
    return now >= start.addingTimeInterval(Double(focusMinutes + exerciseMinutes) * 60)
  }
  public var plannedStart: Date?
  public var nextStartReminderAt: Date?
  public var startReminderDismissed: Bool?
  public init(
    day: String, title: String, focusMinutes: Int = 30, exerciseMinutes: Int = 10,
    exercise: String = ""
  ) {
    self.day = day
    self.title = title
    self.focusMinutes = [15, 30, 45].contains(focusMinutes) ? focusMinutes : 30
    self.exerciseMinutes = min(15, max(0, exerciseMinutes))
    self.exercise = exercise.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
public struct FocusTimer: Codable, Sendable {
  public var taskID: UUID
  public var phase: Phase
  public var duration: Double
  public var elapsed: Double = 0
  public var pauseShiftedAt: Date?
  public var delayedTaskIDs: [UUID]?
  public var paused = false
  public var awaitingReflection = false
  public var startedAt: Date?
  public var endedAt: Date?
  public var advanceReminderMinutes: [Int]?
  public var remaining: Double { max(0, duration - elapsed) }
  public init(taskID: UUID, phase: Phase, duration: Double) {
    self.taskID = taskID
    self.phase = phase
    self.duration = max(1, duration)
    self.startedAt = Date()
  }
  /// Large gaps mean sleep, suspended process, or clock discontinuity; require explicit resume.
  public mutating func advance(by delta: Double) -> Bool {
    guard !paused && !awaitingReflection else { return false }
    guard delta >= 0 && delta <= 10 else {
      paused = true
      return false
    }
    elapsed = min(duration, elapsed + delta)
    if elapsed >= duration {
      awaitingReflection = true
      paused = true
      return true
    }
    return false
  }
}
public struct ChatMessage: Codable, Identifiable, Sendable {
  public var id = UUID()
  public var date = Date()
  public var role: String
  public var content: String
  public var kind: String
  public var taskID: UUID?
  public var phase: Phase?
  public var dialogueScene: String?
  public var dialoguePhrase: String?
  public var dialogueLanguage: String?
  public var dialoguePersona: String?
  public init(role: String, content: String, kind: String = "chat") {
    self.role = role
    self.content = content
    self.kind = kind
  }
}
public struct SavedMemory: Codable, Identifiable, Sendable {
  public var id = UUID()
  public var text: String
  public var date = Date()
  public init(text: String) { self.text = text }
}
public struct AnalysisReport: Codable, Identifiable, Sendable {
  public var id = UUID()
  public var date = Date()
  public var period: String
  public var content: String
  public init(period: String, content: String) {
    self.period = period
    self.content = content
  }
}
public struct SavedReadingBook: Codable, Identifiable, Sendable, Equatable {
  public var id: UUID
  public var title: String
  public var author: String
  public var insights: [String]
  public init(id: UUID = UUID(), title: String, author: String, insights: [String]) {
    self.id = id; self.title = title; self.author = author; self.insights = insights
  }
}
public struct Preferences: Codable, Sendable {
  public var desktopCharacterID: String?
  public var idleCompanionEnabled: Bool? = true
  public var advanceRemindersEnabled: Bool? = true
  public var lastIdleCompanionAt: Date?
  public var lastWeatherMorningDay: String?
  public var lastWeatherEveningDay: String?
  public var lastWakeGreetingDay: String?
  public var readingBookTitle: String?
  public var readingBookAuthor: String?
  public var readingBookInsights: [String]?
  public var readingBookShelf: [SavedReadingBook]?
  public var speechEnabled: Bool? = true
  public var aiEnabled = false
  public var autoGreeting = false
  public var automaticLearning: Bool?
  /// `deepseek`, `openai`, or `openai-compatible`. Optional for old backups.
  public var aiProvider: String?
  /// Full OpenAI-compatible chat-completions endpoint. Optional for presets.
  public var aiEndpoint: String?
  public var model = "deepseek-chat"
  public var sound = true
  public var interfaceLanguage: String?
  public var voiceLanguage: String?
  public var activityTags: [String]?
  public var clonedSpeechEnabled: Bool?
  public var spokenChatReplies: Bool?
  public var clonedVoiceID: String?
  public var spokenReminders: Bool?
  public var spokenTaskReplies: Bool?
  public var alwaysOnTop = true
  public var petHeight: Double = 300
  public init() {}
}
public struct AppState: Codable, Sendable {
  public var schemaVersion = 1
  public var tasks: [PlanTask] = []
  public var timer: FocusTimer?
  public var messages: [ChatMessage] = []
  public var memories: [SavedMemory] = []
  public var dialogueVotes: [DialogueVote]?
  public var dialogueReplays: [DialogueVote]?
  public var learning: LearningState?
  public var reports: [AnalysisReport] = []
  public var preferences = Preferences()
  public var voicePacks: [String: VoicePack]?
  public var voiceLines: [String: String]?
  public var voiceSignature: String?
  public var voiceSpeaker: String?
  public var companion: CompanionProfile?
  public var onboarding: OnboardingState?
  public var knowledge: CompanionKnowledge?
  public var knowledgeVersions: [CompanionKnowledgeVersion]?
  public var historicalRecords: [HistoricalMessage]?
  public var greetingDay = ""
  public var aiRequests = 0
  public var aiTokens = 0
  public var historyEnabled = true
  public init() {}
  public func validate() throws {
    guard schemaVersion == 1, Set(tasks.map(\.id)).count == tasks.count else {
      throw DataError.invalid
    }
    for t in tasks {
      guard [15, 30, 45].contains(t.focusMinutes), (0...15).contains(t.exerciseMinutes),
        Day.parse(t.day) != nil
      else { throw DataError.invalid }
      for r in [t.focus, t.movement] {
        if let start = r.startedAt, let end = r.endedAt, end < start { throw DataError.invalid }
        guard r.seconds.isFinite, r.seconds >= 0, r.score == nil || (0...10).contains(r.score!)
        else { throw DataError.invalid }
      }
    }
    if let timer {
      guard tasks.contains(where: { $0.id == timer.taskID && !$0.cancelled }),
        timer.duration.isFinite, timer.duration > 0, timer.elapsed.isFinite, timer.elapsed >= 0,
        timer.elapsed <= timer.duration
      else { throw DataError.invalid }
    }
    guard (180...500).contains(preferences.petHeight)
    else { throw DataError.invalid }
  }
}
public enum DataError: Error { case invalid }
public enum Day {
  public static func key(_ date: Date = Date()) -> String {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
  }
  public static func parse(_ key: String) -> Date? {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    f.isLenient = false
    return f.date(from: key)
  }
}
public struct Statistics {
  public let tasks: [PlanTask]
  public init(tasks: [PlanTask]) { self.tasks = tasks.filter { !$0.cancelled && $0.deletedAt == nil } }
  public var planned: Int { tasks.count }
  public func expired(at now: Date = Date(), activeTaskID: UUID? = nil) -> Int { tasks.filter { $0.isExpired(at: now, activeTaskID: activeTaskID) }.count }
  public var focusDone: Int { tasks.filter { $0.focus.outcome == .done }.count }
  public var exercisePlanned: Int { tasks.filter { $0.exerciseMinutes > 0 }.count }
  public var exerciseDone: Int { tasks.filter { $0.exerciseMinutes > 0 && $0.movement.outcome == .done }.count }
  public var completeRounds: Int {
    tasks.filter { $0.focus.outcome == .done && ($0.exerciseMinutes == 0 || $0.movement.outcome == .done) }.count
  }
  public func scores(_ phase: Phase) -> [Int] {
    tasks.compactMap { phase == .focus ? $0.focus.score : ($0.exerciseMinutes > 0 ? $0.movement.score : nil) }
  }
  public func average(_ phase: Phase) -> Double? {
    let s = scores(phase)
    return s.isEmpty ? nil : Double(s.reduce(0, +)) / Double(s.count)
  }
  public func minutes(_ phase: Phase) -> Double {
    tasks.reduce(0) { $0 + (phase == .focus ? $1.focus.seconds : ($1.exerciseMinutes > 0 ? $1.movement.seconds : 0)) } / 60
  }
  public func rate(_ phase: Phase) -> Double? {
    let count = phase == .focus ? planned : exercisePlanned
    return count == 0 ? nil : Double(phase == .focus ? focusDone : exerciseDone) / Double(count)
  }
}
public final class StateFile {
  public let url: URL
  public init(url: URL) { self.url = url }
  public func load() throws -> AppState {
    guard FileManager.default.fileExists(atPath: url.path) else { return AppState() }
    let state = try JSONDecoder().decode(AppState.self, from: Data(contentsOf: url))
    try state.validate()
    return state
  }
  public func save(_ state: AppState) throws {
    try state.validate()
    let fm = FileManager.default
    try fm.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(state)
    if fm.fileExists(atPath: url.path) {
      // Validate before rotating: never replace the last good backup with corrupt data.
      _ = try load()
      try Data(contentsOf: url).write(to: url.appendingPathExtension("backup"), options: [.atomic])
      try fm.setAttributes(
        [.posixPermissions: 0o600], ofItemAtPath: url.appendingPathExtension("backup").path)
    }
    try data.write(to: url, options: [.atomic])
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
