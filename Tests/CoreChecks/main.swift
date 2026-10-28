import Foundation
import StillWithYouCore

// Standalone behavior checks: Command Line Tools does not bundle XCTest.
func XCTAssertTrue(
  _ value: @autoclosure () -> Bool, file: StaticString = #fileID, line: UInt = #line
) { precondition(value(), "\(file):\(line)") }
func XCTAssertFalse(
  _ value: @autoclosure () -> Bool, file: StaticString = #fileID, line: UInt = #line
) { precondition(!value(), "\(file):\(line)") }
func XCTAssertEqual<T: Equatable>(
  _ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T
) rethrows {
  let x = try a()
  let y = try b()
  precondition(x == y, "Expected \(y), got \(x)")
}
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T) {
  do { _ = try expression() } catch { return }
  preconditionFailure("Expected an error")
}

final class CoreTests {
  func testCompanionClockUsesDeviceTime() {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let evening = formatter.date(from: "2026-10-07T10:50:00Z")! // 18:50 in China
    let morning = formatter.date(from: "2026-10-07T22:30:00Z")! // 06:30 in China
    XCTAssertTrue(CompanionClock.context(at: evening).contains("18:50"))
    XCTAssertTrue(CompanionClock.context(at: morning).contains("06:30"))
    XCTAssertTrue(CompanionClock.context(at: evening).contains("设备本地时间"))
  }
  func testCompanionSleepCueAndWakeCycleUseChinaTime() {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let beforeSleep = formatter.date(from: "2026-10-07T21:59:00Z")! // 05:59 China
    let sleepStart = formatter.date(from: "2026-10-07T22:00:00Z")! // 06:00 China
    let sleepEnd = formatter.date(from: "2026-10-07T10:00:00Z")! // 18:00 China
    let afterMidnight = formatter.date(from: "2026-10-07T16:00:00Z")! // 00:00 next day China
    XCTAssertFalse(CompanionSchedule.isSleeping(at: beforeSleep))
    XCTAssertTrue(CompanionSchedule.isSleeping(at: sleepStart))
    XCTAssertTrue(CompanionSchedule.isSleeping(at: formatter.date(from: "2026-10-07T09:59:00Z")!))
    XCTAssertFalse(CompanionSchedule.isSleeping(at: sleepEnd))
    XCTAssertTrue(CompanionSchedule.isAwakeCycle(at: afterMidnight))
    XCTAssertEqual(CompanionSchedule.wakeCycleDay(at: afterMidnight), "2026-10-07")
  }
  func testTimerStopsAtDeadlineAndDoesNotCompleteTaskAutomatically() {
    let task = PlanTask(day: "2026-09-28", title: "阅读", focusMinutes: 15)
    var timer = FocusTimer(taskID: task.id, phase: .focus, duration: 900)
    for _ in 0..<899 { XCTAssertFalse(timer.advance(by: 1)) }
    XCTAssertEqual(timer.remaining, 1)
    XCTAssertTrue(timer.advance(by: 1))
    XCTAssertTrue(timer.awaitingReflection)
    XCTAssertTrue(timer.paused)
    XCTAssertFalse(timer.advance(by: 1))
    XCTAssertEqual(task.focus.outcome, .pending)
  }
  func testSleepGapAndPausedTimeNeverCountAsExercise() {
    var timer = FocusTimer(taskID: UUID(), phase: .exercise, duration: 600)
    _ = timer.advance(by: 5)
    _ = timer.advance(by: 3600)
    XCTAssertTrue(timer.paused)
    XCTAssertEqual(timer.elapsed, 5)
    _ = timer.advance(by: 1)
    XCTAssertEqual(timer.elapsed, 5)
    timer.paused = false
    _ = timer.advance(by: 2)
    XCTAssertEqual(timer.elapsed, 7)
  }
  func testStatisticsKeepUnratedSeparateFromZeroAndExcludeCancelled() {
    var a = PlanTask(day: "2026-09-28", title: "A")
    a.focus = Reflection(outcome: .done, score: 0, seconds: 900)
    var b = PlanTask(day: "2026-09-28", title: "B")
    b.focus = Reflection(outcome: .partial, score: 8, seconds: 600)
    b.movement = Reflection(outcome: .done, score: nil, seconds: 600)
    let c = PlanTask(day: "2026-09-28", title: "C")
    var d = PlanTask(day: "2026-09-28", title: "D")
    d.cancelled = true
    d.focus = Reflection(outcome: .done, score: 10)
    let stats = Statistics(tasks: [a, b, c, d])
    XCTAssertEqual(stats.planned, 3)
    XCTAssertEqual(stats.focusDone, 1)
    XCTAssertEqual(stats.exerciseDone, 1)
    XCTAssertEqual(stats.completeRounds, 0)
    XCTAssertEqual(stats.average(.focus), 4)
    XCTAssertEqual(stats.scores(.focus).count, 2)
    XCTAssertNil(stats.average(.exercise))
    XCTAssertEqual(stats.minutes(.focus), 25)
    XCTAssertNil(Statistics(tasks: []).rate(.focus))
  }
  func testPersistenceRoundTripAndCorruptionDoesNotOverwriteBackup() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = StateFile(url: folder.appendingPathComponent("state.json"))
    var state = AppState()
    state.tasks = [PlanTask(day: "2026-09-28", title: "记住我")]
    state.preferences.desktopCharacterID = "duo-sleeveless"
    let savedBook = SavedReadingBook(title: "纳瓦尔宝典", author: "埃里克·乔根森", insights: ["长期思考比短期忙碌更重要。"])
    state.preferences.readingBookShelf = [savedBook]
    try file.save(state)
    state.messages = [ChatMessage(role: "user", content: "你好")]
    try file.save(state)
    try XCTAssertEqual(try file.load().messages.first?.content, "你好")
    try XCTAssertEqual(try file.load().preferences.readingBookShelf, [savedBook])
    try XCTAssertEqual(try file.load().preferences.desktopCharacterID, "duo-sleeveless")
    let backup = try Data(contentsOf: file.url.appendingPathExtension("backup"))
    try Data("broken".utf8).write(to: file.url)
    XCTAssertThrowsError(try file.load())
    XCTAssertThrowsError(try file.save(state))
    try XCTAssertEqual(try Data(contentsOf: file.url.appendingPathExtension("backup")), backup)
  }
  func testRestoreRejectsDanglingTimerAndInvalidScore() {
    var state = AppState()
    state.timer = FocusTimer(taskID: UUID(), phase: .focus, duration: 900)
    XCTAssertThrowsError(try state.validate())
    state.timer = nil
    var task = PlanTask(day: "2026-09-28", title: "读书")
    task.focus.score = 11
    state.tasks = [task]
    XCTAssertThrowsError(try state.validate())
  }
}

let suite = CoreTests()
suite.testCompanionClockUsesDeviceTime()
suite.testCompanionSleepCueAndWakeCycleUseChinaTime()
suite.testTimerStopsAtDeadlineAndDoesNotCompleteTaskAutomatically()
suite.testSleepGapAndPausedTimeNeverCountAsExercise()
suite.testStatisticsKeepUnratedSeparateFromZeroAndExcludeCancelled()
try suite.testPersistenceRoundTripAndCorruptionDoesNotOverwriteBackup()
suite.testRestoreRejectsDanglingTimerAndInvalidScore()
print("PASS: 5 behavior checks — timer, sleep, statistics, persistence, invalid restore")

// Old settings must load without new profile/history keys, and obsolete mail settings are ignored.
var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppState())) as! [String: Any]
legacy.removeValue(forKey: "companion")
legacy.removeValue(forKey: "historicalRecords")
var oldPreferences = legacy["preferences"] as! [String: Any]
oldPreferences["mailEnabled"] = true
oldPreferences["smtpPort"] = 465
legacy["preferences"] = oldPreferences
legacy["mailAttempts"] = [["detail": "obsolete"]]
var migrated = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: legacy))
try migrated.validate()
XCTAssertEqual((migrated.companion ?? CompanionProfile()).displayName, "陪伴者")
var profile = CompanionProfile()
profile.name = "小雨"
profile.userName = "阿哲"
profile.description = "她是温柔的图书管理员，喜欢猫。"
migrated.companion = profile
XCTAssertTrue(profile.systemPrompt.contains("小雨"))
XCTAssertTrue(profile.systemPrompt.contains("阿哲"))
XCTAssertFalse(profile.systemPrompt.contains("称呼用户：你。"))
let json = Data("[{\"role\":\"user\",\"content\":\"你好\"},{\"role\":\"assistant\",\"content\":\"下午好\"}]".utf8)
let imported = try HistoryImporter.parse(data: json, fileExtension: "json")
XCTAssertEqual(imported.count, 2)
XCTAssertEqual(imported[1].speaker, "assistant")
XCTAssertEqual(HistoryImporter.merging(imported, into: imported).count, 2)
let markdown = try HistoryImporter.parse(data: Data(("# 一段历史\n我：今天去散步了。\n她：真好。\n" + String(repeating: "文字", count: 1200)).utf8), fileExtension: "md")
XCTAssertTrue(markdown.count >= 3)
XCTAssertTrue(markdown.allSatisfy { $0.text.count <= 1000 })
XCTAssertTrue(markdown.contains { $0.speaker == "我" && $0.text.contains("今天去散步了") })
XCTAssertTrue(markdown.contains { $0.speaker == "她" && $0.text.contains("真好") })
XCTAssertEqual(Set(HistoryImportPolicy.candidates(in: markdown).map(\.name)), Set(["我", "她"]))
let plainNotes = try HistoryImporter.parse(
  data: Data("标题：今天的记录\n地点：上海\n这里只是普通笔记。".utf8), fileExtension: "txt")
XCTAssertEqual(Set(plainNotes.map(\.speaker)), Set(["历史原文"]))
let weFlow = """
# 测试会话

- 会话ID: `123@chatroom`
- 会话类型: 群聊
- 导出时间: 2026\\-07\\-28 13:07:45
- 导出工具: WeFlow

---

## 2026\\-04\\-11 19:56:50 阿岚

带伞，别淋着。

## 2026\\-04\\-11 19:57:02 我

> 阿岚: 带伞

知道了。
"""
let weFlowRecords = try HistoryImporter.parse(data: Data(weFlow.utf8), fileExtension: "md")
XCTAssertEqual(weFlowRecords.count, 2)
XCTAssertEqual(weFlowRecords.map(\.speaker), ["阿岚", "我"])
XCTAssertEqual(weFlowRecords[0].timestamp, "2026-04-11 19:56:50")
XCTAssertEqual(weFlowRecords[0].sourceID, "weflow:123@chatroom")
XCTAssertEqual(weFlowRecords.map(\.sourceIndex), [0, 1])
XCTAssertTrue(weFlowRecords[1].text.contains("> 阿岚: 带伞"))
XCTAssertFalse(HistoryImportPolicy.candidates(in: weFlowRecords).contains { $0.name == "会话ID" })
let anotherChat = weFlow.replacingOccurrences(of: "123@chatroom", with: "other-chat")
let anotherChatRecords = try HistoryImporter.parse(
  data: Data(anotherChat.utf8), fileExtension: "md")
XCTAssertEqual(HistoryImporter.merging(anotherChatRecords, into: weFlowRecords).count, 4)
XCTAssertEqual(HistoryImporter.merging(weFlowRecords, into: weFlowRecords).count, 2)
var firstBatch = [
  HistoricalMessage(speaker: "我", text: "到家了"),
  HistoricalMessage(speaker: "她", text: "你好呀"),
]
firstBatch = HistorySpeakerAssignment.markingPending(firstBatch, imported: firstBatch)
XCTAssertTrue(firstBatch.allSatisfy { $0.isCompanion == nil })
firstBatch = HistorySpeakerAssignment.confirming(
  "她", candidates: ["我", "她"], recordKeys: Set(firstBatch.map(\.duplicateKey)), in: firstBatch)
XCTAssertEqual(HistorySpeakerAssignment.confirmedNames(in: firstBatch), ["她"])
let secondBatch = [
  HistoricalMessage(speaker: "user", text: "晚安"),
  HistoricalMessage(speaker: "assistant", text: "来啦"),
]
let allBatches = HistorySpeakerAssignment.confirming(
  "assistant", candidates: ["user", "assistant"], recordKeys: Set(secondBatch.map(\.duplicateKey)),
  in: firstBatch + secondBatch)
XCTAssertEqual(Set(HistorySpeakerAssignment.confirmedNames(in: allBatches)), Set(["她", "assistant"]))
XCTAssertTrue(HistorySpeakerAssignment.unresolved(in: allBatches).isEmpty)
let reReviewed = HistorySpeakerAssignment.addingCompanionAlias(
  "她", recordKeys: Set(allBatches.map(\.duplicateKey)), in: allBatches)
XCTAssertEqual(Set(HistorySpeakerAssignment.confirmedNames(in: reReviewed)), Set(["她", "assistant"]))
XCTAssertEqual(
  Set(CharacterVoice.samples(scene: "greeting", history: allBatches, speaker: nil)),
  Set(["你好呀", "来啦"]))
XCTAssertThrowsError(try HistoryImporter.parse(data: Data("{bad json}".utf8), fileExtension: "json"))
XCTAssertThrowsError(try HistoryImporter.parse(data: Data(" ".utf8), fileExtension: "txt"))
XCTAssertThrowsError(try HistoryImporter.parse(data: Data("{\"text\":\"有效\"}\n{bad}".utf8), fileExtension: "jsonl"))
migrated.historicalRecords = imported
let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(migrated))
XCTAssertEqual(restored.companion, profile)
XCTAssertEqual(restored.historicalRecords?.count, 2)
let exported = String(data: try JSONEncoder().encode(restored), encoding: .utf8)!
XCTAssertFalse(exported.contains("mailEnabled"))
XCTAssertFalse(exported.contains("smtp"))
print("PASS: legacy migration, custom persona, history formats, deduplication, invalid imports, complete backup round-trip")

let reminderTask = PlanTask(day: "2026-09-28", title: "阅读第三章", exerciseMinutes: 12, exercise: "拉伸")
let focusReminder = DeadlineReminder.text(task: reminderTask, phase: .focus, profile: profile)
XCTAssertTrue(focusReminder.contains("阿哲"))
XCTAssertTrue(focusReminder.contains("阅读第三章"))
XCTAssertTrue(focusReminder.contains("12 分钟"))
let exerciseReminder = DeadlineReminder.text(task: reminderTask, phase: .exercise, profile: profile)
XCTAssertTrue(exerciseReminder.contains("拉伸"))
XCTAssertTrue(exerciseReminder.contains("运动时间到"))
XCTAssertTrue((restored.preferences.spokenReminders ?? true))
print("PASS: task-specific focus/exercise reminders and old-settings voice default")

var noActivity = PlanTask(day: "2026-09-28", title: "只读书", exerciseMinutes: 0)
noActivity.focus = Reflection(outcome: .done, score: 9)
var onlyFocusState = AppState()
onlyFocusState.tasks = [noActivity]
try onlyFocusState.validate()
let zeroStats = Statistics(tasks: [noActivity])
XCTAssertEqual(noActivity.exerciseMinutes, 0)
XCTAssertEqual(zeroStats.exercisePlanned, 0)
XCTAssertEqual(zeroStats.exerciseDone, 0)
XCTAssertEqual(zeroStats.completeRounds, 1)
XCTAssertNil(zeroStats.rate(.exercise))
XCTAssertEqual(Statistics(tasks: [noActivity, reminderTask]).exercisePlanned, 1)
XCTAssertTrue(DeadlineReminder.text(task: noActivity, phase: .focus, profile: profile).contains("没有安排活动"))
XCTAssertEqual(PlanTask(day: "2026-09-28", title: "喝水", exerciseMinutes: 1, exercise: "喝水").exerciseMinutes, 1)
print("PASS: zero/short activity, completion and activity rate denominator, no-activity reminder")

var planningCalendar = Calendar(identifier: .gregorian)
planningCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
let iso = ISO8601DateFormatter()
let at1050 = iso.date(from: "2026-09-28T10:50:00Z")!
let at11 = iso.date(from: "2026-09-28T11:00:00Z")!
let noon = iso.date(from: "2026-09-28T12:00:00Z")!
XCTAssertEqual(DayPlanner.roundedHour(at1050, calendar: planningCalendar), at11)
XCTAssertEqual(DayPlanner.roundedHour(at11, calendar: planningCalendar), at11)
XCTAssertEqual(DayPlanner.slots(start: at11, end: noon).count, 1)
XCTAssertEqual(DayPlanner.slots(start: at1050, end: noon).count, 1)
XCTAssertEqual(DayPlanner.slots(start: noon, end: at11).count, 0)
let at14 = iso.date(from: "2026-09-28T14:00:00Z")!
let at18 = iso.date(from: "2026-09-28T18:00:00Z")!
let afternoonSlots = DayPlanner.slots(start: at14, end: at18)
XCTAssertEqual(afternoonSlots.count, 4)
XCTAssertEqual(afternoonSlots.last!.addingTimeInterval(3600), at18)
var scheduledTask = PlanTask(day: "2026-09-28", title: "有时间的计划", focusMinutes: 45, exerciseMinutes: 15)
scheduledTask.plannedStart = at14
let restoredTask = try JSONDecoder().decode(PlanTask.self, from: JSONEncoder().encode(scheduledTask))
XCTAssertEqual(restoredTask.plannedStart, at14)
print("PASS: rounded start, morning/afternoon slots, invalid ranges, scheduled task persistence")

XCTAssertFalse(DayPlanner.canSchedule(start: at11, now: at11.addingTimeInterval(1)))
XCTAssertTrue(DayPlanner.canSchedule(start: at11, now: at1050))
XCTAssertTrue(DayPlanner.canSchedule(start: at11, now: at11))
XCTAssertFalse(DayPlanner.canSchedule(start: at1050, now: at14))
XCTAssertTrue(DayPlanner.canSchedule(start: at14.addingTimeInterval(86400), now: at18))
print("PASS: past start rejected, future and exact starts allowed, expired preview blocked")

var dueTask = scheduledTask
dueTask.day = Day.key(at14)
XCTAssertFalse(DayPlanner.needsStartReminder(dueTask, now: at14.addingTimeInterval(-1), activeTaskID: nil))
XCTAssertTrue(DayPlanner.needsStartReminder(dueTask, now: at14, activeTaskID: nil))
XCTAssertFalse(DayPlanner.needsStartReminder(dueTask, now: at14, activeTaskID: dueTask.id))
dueTask.focus.startedAt = at14.addingTimeInterval(-600)
XCTAssertFalse(DayPlanner.needsStartReminder(dueTask, now: at14, activeTaskID: nil))
dueTask.focus.startedAt = nil
dueTask.nextStartReminderAt = at14.addingTimeInterval(300)
XCTAssertFalse(DayPlanner.needsStartReminder(dueTask, now: at14.addingTimeInterval(299), activeTaskID: nil))
XCTAssertTrue(DayPlanner.needsStartReminder(dueTask, now: at14.addingTimeInterval(300), activeTaskID: nil))
dueTask.startReminderDismissed = true
XCTAssertFalse(DayPlanner.needsStartReminder(dueTask, now: at14.addingTimeInterval(301), activeTaskID: nil))
var timedRecord = Reflection(outcome: .done, seconds: 900, recordedAt: at14.addingTimeInterval(1000))
timedRecord.startedAt = at14
timedRecord.endedAt = at14.addingTimeInterval(900)
let timedCopy = try JSONDecoder().decode(Reflection.self, from: JSONEncoder().encode(timedRecord))
XCTAssertEqual(timedCopy.startedAt, timedRecord.startedAt)
XCTAssertEqual(timedCopy.endedAt, timedRecord.endedAt)
XCTAssertEqual(timedCopy.recordedAt, timedRecord.recordedAt)
var badTimes = AppState()
dueTask.focus = timedRecord
dueTask.focus.endedAt = at14.addingTimeInterval(-1)
badTimes.tasks = [dueTask]
XCTAssertThrowsError(try badTimes.validate())
print("PASS: scheduled confirmation due/early/snoozed/dismissed, actual times persisted, invalid time range rejected")

// Character phrasing must not learn the user's lines or reuse stale settings.
do {
  let p = CompanionProfile()
  let pending = [HistoricalMessage(speaker: "我", text: "加油用户原话"),
    HistoricalMessage(speaker: "她", text: "加油呀")]
  precondition(CharacterVoice.speaker(history: pending, profile: p, selected: nil) == nil)
  precondition(CharacterVoice.samples(scene: "start", history: pending, speaker: nil).isEmpty)
  let history = [HistoricalMessage(speaker: "我", text: "加油用户原话", isCompanion: false),
    HistoricalMessage(speaker: "旧名字", text: "慢慢来，不着急", isCompanion: true),
    HistoricalMessage(speaker: "旧名字", text: "加油呀", isCompanion: true),
    HistoricalMessage(speaker: "旧名字", text: "加油呀", isCompanion: true)]
  let speaker = CharacterVoice.speaker(history: history, profile: p, selected: nil)
  precondition(speaker == "旧名字")
  precondition(CharacterVoice.samples(scene: "start", history: history, speaker: speaker) == ["加油呀"])
  precondition(CharacterVoice.samples(scene: "greeting", history: history, speaker: speaker).isEmpty)
  precondition(CharacterVoice.speaker(history: history + [HistoricalMessage(speaker: "另一个人", text: "你好")], profile: p, selected: nil) == "旧名字")
  let signature = CharacterVoice.signature(profile: p, history: history, selected: nil, enabled: true)
  precondition(signature != CharacterVoice.signature(profile: p, history: history, selected: nil, enabled: false))
  var changed = p; changed.description = "严肃简洁"
  precondition(signature != CharacterVoice.signature(profile: changed, history: history, selected: nil, enabled: true))
  let lines = Dictionary(uniqueKeysWithValues: CharacterVoice.scenes.keys.map { ($0, (1...5).map { "测试用语\($0)" }) })
  let json = String(data: try JSONEncoder().encode(lines), encoding: .utf8)!
  let decodedLines = try CharacterVoice.decode(json)
  precondition(decodedLines == lines)
  do { _ = try CharacterVoice.decode("{\"today\":\"不完整\"}"); fatalError("invalid voice accepted") } catch {}
  print("PASS: companion-only phrases, scene relevance, ambiguous speaker, voice cache invalidation, complete response validation")
}

do {
  var pet = PetInteractions()
  var reactions: [PetReaction] = []
  for i in 0...90 {
    let angle = Double(i) * 0.16
    if let event = pet.pointer(x: 150 * cos(angle), y: 150 * sin(angle), at: Double(i) * 0.06) { reactions.append(event) }
  }
  precondition(reactions == [.dizzy])
  pet.beginDrag(x: 0, y: 0, at: 6)
  _ = pet.drag(x: 100, y: 0, at: 6.06)
  precondition(pet.drag(x: 350, y: 0, at: 6.15) == nil) // shared cooldown
  pet.endDrag()
  var shake = PetInteractions()
  var shakeEvents: [PetReaction] = []
  for i in 0...150 {
    if let event = shake.pointer(x: 150, y: i % 2 == 0 ? 50 : -50, at: Double(i) * 0.06) { shakeEvents.append(event) }
  }
  precondition(shakeEvents == [.dizzy])
  var fast = PetInteractions()
  fast.beginDrag(x: 0, y: 0, at: 0)
  _ = fast.drag(x: 100, y: 0, at: 0.06)
  precondition(fast.drag(x: 250, y: 0, at: 0.15) == .fastDrag)
  var repeated = PetInteractions()
  for i in 0..<4 {
    repeated.beginDrag(x: 0, y: 0, at: Double(i))
    let event = repeated.drag(x: 20, y: 0, at: Double(i) + 0.2)
    precondition(event == (i == 3 ? .repeatedDrag : nil))
    repeated.endDrag()
  }
  var clicks = PetInteractions()
  for i in 0..<6 {
    clicks.beginDrag(x: 0, y: 0, at: Double(i))
    precondition(clicks.drag(x: 2, y: 0, at: Double(i) + 0.2) == nil)
    clicks.endDrag()
  }
  var distant = PetInteractions()
  for i in 0...90 {
    let angle = Double(i) * 0.16
    precondition(distant.pointer(x: 600 * cos(angle), y: 600 * sin(angle), at: Double(i) * 0.06) == nil)
  }
  print("PASS: pet circles, fast/repeated drag, shared cooldown, pointer shake detected, normal clicks and distant pointer ignored")
}

do {
  let cases: [(Double, Double, Bool, PetReaction)] = [
    (0.5, 1, false, .top), (0.5, 0, false, .bottom), (0, 1, false, .corner),
    (0, 0.5, false, .left), (1, 0.5, false, .right), (0.5, 0.5, false, .center),
    (0.5, 1, true, .screenChange)
  ]
  for (x, y, cross, expected) in cases {
    var pet = PetInteractions()
    pet.beginDrag(x: 0, y: 0, at: 0)
    _ = pet.drag(x: 30, y: 0, at: 0.2)
    precondition(pet.drop(x: x, y: y, crossedScreen: cross, at: 0.3) == expected)
    precondition(pet.drop(x: x, y: y, crossedScreen: cross, at: 0.4) == nil)
  }
  var hover = PetInteractions()
  var events: [PetReaction] = []
  for i in 0..<600 {
    if let event = hover.pointer(x: 120, y: 0, at: Double(i) * 0.06) { events.append(event) }
  }
  precondition(events == [.hover])
  var long = PetInteractions()
  long.beginDrag(x: 0, y: 0, at: 0)
  for i in 1...30 { _ = long.drag(x: Double(i * 20), y: 0, at: Double(i) * 0.2) }
  precondition(long.drop(x: 0.5, y: 0.5, crossedScreen: false, at: 6.1) == .longDrag)
  precondition(PetReaction.allCases.allSatisfy { Set($0.lines).count == 3 })
  print("PASS: edge/corner/center placement, cross-screen priority, long drag, hover once per visit, three distinct phrases per reaction")
}

do {
  var pet = PetInteractions()
  var events: [PetReaction] = []
  for i in 0..<100 {
    if let event = pet.reach(x: 2, y: 1, at: Double(i) * 0.06) { events.append(event) }
  }
  precondition(events == [.reach])
  precondition(pet.reach(x: 40, y: 0, at: 6.1) == nil)
  for i in 0..<30 { precondition(pet.reach(x: 1, y: 1, at: 6.2 + Double(i) * 0.06) == nil) }
  var moving = PetInteractions()
  for i in 0..<60 { precondition(moving.reach(x: i % 2 == 0 ? -5 : 5, y: 0, at: Double(i) * 0.06) == nil) }
  var paused = PetInteractions()
  _ = paused.reach(x: 0, y: 0, at: 0)
  precondition(paused.reach(x: 0, y: 0, at: 8) == nil)
  print("PASS: fingertip dwell, one touch per visit, shared cooldown, moving/far pointer and interruption ignored")
}

do {
  precondition(VoiceLanguage.allCases.count == 9)
  for language in VoiceLanguage.allCases {
    let bank = VoiceCatalog.reactions[language.rawValue]!
    precondition(Set(bank.keys) == Set(PetReaction.allCases.map(\.rawValue)))
    for choices in bank.values { precondition(choices.count == 5 && Set(choices).count == 5) }
    for scene in CharacterVoice.scenes.keys where !PetReaction.allCases.map(\.rawValue).contains(scene) {
      precondition(VoiceCatalog.templates[language.rawValue]?[scene] != nil)
    }
    let task = PlanTask(day: Day.key(), title: "Demo", exerciseMinutes: 10, exercise: "Walk")
    let text = DeadlineReminder.text(task: task, phase: .focus, profile: CompanionProfile(), language: language)
    precondition(text.contains("Demo") && text.contains("Walk") && text.contains("10") && !text.contains("{task}"))
  }
  var deck = PhraseDeck()
  let choices = ["a", "b", "c", "d", "e"]
  var previous = ""
  for _ in 0..<20 {
    var cycle: [String] = []
    for _ in 0..<5 {
      let line = deck.next(key: "test", choices: choices)
      precondition(line != previous)
      previous = line; cycle.append(line)
    }
    precondition(Set(cycle) == Set(choices))
  }
  precondition(CharacterVoice.signature(profile: CompanionProfile(), history: [], selected: nil, enabled: true, language: .en) != CharacterVoice.signature(profile: CompanionProfile(), history: [], selected: nil, enabled: true, language: .ja))
  let lines = Dictionary(uniqueKeysWithValues: CharacterVoice.scenes.keys.map { ($0, choices) })
  var state = AppState(); state.preferences.voiceLanguage = "ar"
  state.voicePacks = ["ar": VoicePack(signature: "example", lines: lines)]
  let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
  precondition(restored.preferences.voiceLanguage == "ar" && restored.voicePacks?["ar"]?.lines == lines)
  print("PASS: nine complete language banks, five unique phrases per reaction, non-repeating shuffle, localized reminder facts, language cache and backup")
}

do {
  let task = PlanTask(day: Day.key(), title: "feedback task", exerciseMinutes: 10)
  var message = ChatMessage(role: "assistant", content: "A localized reminder", kind: "reminder")
  message.taskID = task.id; message.phase = .exercise
  let copy = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message))
  precondition(FeedbackLink.resolve(copy, tasks: [task])?.phase == .exercise)
  precondition(FeedbackLink.resolve(copy, tasks: []) == nil)
  let legacy = ChatMessage(role: "assistant", content: "「feedback task」的专注时间到啦。", kind: "reminder")
  precondition(FeedbackLink.resolve(legacy, tasks: [task])?.task.id == task.id)
  var duplicate = task; duplicate.id = UUID()
  precondition(FeedbackLink.resolve(legacy, tasks: [task, duplicate]) == nil)
  precondition(FeedbackLink.resolve(ChatMessage(role: "assistant", content: legacy.content), tasks: [task]) == nil)
  print("PASS: feedback links persist task/phase, resolve legacy reminders, reject ambiguous/missing targets and ordinary chat")
}


do {
  var pet = PetInteractions()
  var touch: PetReaction?
  for i in 0...25 { if let event = pet.reach(x: 22, y: 0, at: Double(i) * 0.06) { touch = event } }
  precondition(touch == .reach)
  pet.beginDrag(x: 0, y: 0, at: 2)
  _ = pet.drag(x: 25, y: 0, at: 2.2)
  precondition(pet.drop(x: 0.5, y: 1, crossedScreen: false, at: 2.3) == .top)
  pet.endDrag()
  pet.beginDrag(x: 0, y: 0, at: 3)
  _ = pet.drag(x: 25, y: 0, at: 3.2)
  precondition(pet.drop(x: 0.5, y: 0, crossedScreen: false, at: 3.3) == .bottom)
  print("PASS: expanded hand target, different placements respond without shared cooldown blocking")
}

do {
  let start = Date(timeIntervalSince1970: 1800000000)
  var task = PlanTask(day: Day.key(start), title: "过期", focusMinutes: 45, exerciseMinutes: 15)
  task.plannedStart = start
  precondition(!task.isExpired(at: start.addingTimeInterval(3599)))
  precondition(task.isExpired(at: start.addingTimeInterval(3600)))
  precondition(!task.isExpired(at: start.addingTimeInterval(3600), activeTaskID: task.id))
  precondition(Statistics(tasks: [task]).expired(at: start.addingTimeInterval(3600)) == 1)
  precondition(Statistics(tasks: [task]).rate(.focus) == 0)
  precondition(Statistics(tasks: [task]).average(.focus) == nil)
  precondition(!DayPlanner.needsStartReminder(task, now: start.addingTimeInterval(3600), activeTaskID: nil))
  task.deletedAt = start
  precondition(Statistics(tasks: [task]).planned == 0)
  task.deletedAt = nil
  task.focus.startedAt = start
  precondition(!task.isExpired(at: start.addingTimeInterval(7200)))
  task.focus.startedAt = nil; task.focus.outcome = .done
  precondition(!task.isExpired(at: start.addingTimeInterval(7200)))
  print("PASS: expiry end boundary, active/started/completed exclusions, denominator and unscored behavior, no expired reminder, deleted exclusion")
}

do {
  let now = Date(timeIntervalSince1970: 1800000000)
  var current = PlanTask(day: Day.key(now), title: "current", focusMinutes: 45, exerciseMinutes: 15)
  current.plannedStart = now
  var next = PlanTask(day: Day.key(now), title: "next")
  next.plannedStart = now.addingTimeInterval(3600)
  var done = next; done.id = UUID(); done.focus.outcome = .done
  var tasks = [current, next, done]
  var timer = FocusTimer(taskID: current.id, phase: .focus, duration: 2700)
  timer.paused = true
  PauseSchedule.advance(tasks: &tasks, timer: &timer, now: now)
  PauseSchedule.advance(tasks: &tasks, timer: &timer, now: now.addingTimeInterval(480))
  precondition(tasks[1].plannedStart == now.addingTimeInterval(4080))
  precondition(tasks[0].plannedStart == now && tasks[2].plannedStart == done.plannedStart)
  PauseSchedule.advance(tasks: &tasks, timer: &timer, now: now.addingTimeInterval(480))
  precondition(tasks[1].plannedStart == now.addingTimeInterval(4080))
  timer = try JSONDecoder().decode(FocusTimer.self, from: JSONEncoder().encode(timer))
  PauseSchedule.advance(tasks: &tasks, timer: &timer, now: now.addingTimeInterval(600))
  precondition(tasks[1].plannedStart == now.addingTimeInterval(4200))
  timer.paused = false
  PauseSchedule.advance(tasks: &tasks, timer: &timer, now: now.addingTimeInterval(900))
  precondition(tasks[1].plannedStart == now.addingTimeInterval(4200))
  print("PASS: eight-minute pause shifts only upcoming unstarted plan, repeated ticks idempotent, saved checkpoint survives reload, running timer does not shift")
}

// Broad proximity works on every side without requiring a fingertip hit.
for point in [(100.0, 0.0), (-100.0, 0.0), (0.0, 120.0), (0.0, -120.0)] {
  var pet = PetInteractions()
  var reactions: [PetReaction] = []
  for i in 0...200 {
    if let reaction = pet.proximity(x: point.0, y: point.1, at: Double(i) * 0.1) { reactions.append(reaction) }
  }
  precondition(reactions == [.reach])
  _ = pet.proximity(x: 500, y: 500, at: 20.1)
  for i in 0...10 {
    if let reaction = pet.proximity(x: point.0, y: point.1, at: 20.2 + Double(i) * 0.1) { reactions.append(reaction) }
  }
  precondition(reactions == [.reach, .reach])
}
do {
  let previous = UIStrings.language
  defer { UIStrings.language = previous }
  for code in ["en", "ja", "ko", "fr", "ru", "pt", "es", "ar"] {
    UIStrings.language = code
    precondition(UIStrings.text("设置") != "设置")
    precondition(UIStrings.text("45 分钟") != "45 分钟")
    precondition(UIStrings.text("我自己的任务内容") == "我自己的任务内容")
  }
  UIStrings.language = "en"
  precondition(UIStrings.text("跟小林说点什么…") == "Say something to 小林…")
}
print("PASS: broad proximity on four sides, one reaction per visit, nine interface languages and preserved custom text")

do {
  var task = PlanTask(day: "2026-09-28", title: "Expired", focusMinutes: 45, exerciseMinutes: 15)
  task.plannedStart = Date(timeIntervalSince1970: 0)
  task.expiryReason = "临时有事"
  task.expiryReasonUpdatedAt = Date()
  let restored = try JSONDecoder().decode(PlanTask.self, from: JSONEncoder().encode(task))
  precondition(restored.expiryReason == "临时有事")
  precondition(restored.isExpired())
  precondition(restored.focus.outcome == .pending && restored.focus.score == nil)
  precondition(restored.movement.outcome == .pending && restored.movement.score == nil)
  print("PASS: expiry reason persists without changing expiry, completion or scores")
}

do {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28))!
  let evening = day.addingTimeInterval(19 * 3600 + 10 * 60)
  let range = DayPlanner.remainingDayRange(day: day, now: evening, calendar: calendar)
  precondition(range.start == day.addingTimeInterval(20 * 3600))
  precondition(range.end == day.addingTimeInterval(24 * 3600))
  precondition(DayPlanner.slots(start: range.start, end: range.end).count == 4)
  let late = DayPlanner.remainingDayRange(day: day, now: day.addingTimeInterval(23 * 3600 + 10 * 60), calendar: calendar)
  precondition(late.start < late.end)
  precondition(DayPlanner.slots(start: late.start, end: late.end, focus: 15, activity: 0).count == 3)
  let afternoon = DayPlanner.remainingDayRange(day: day, now: day.addingTimeInterval(13 * 3600), calendar: calendar)
  precondition(afternoon.start == day.addingTimeInterval(14 * 3600))
  precondition(afternoon.end == day.addingTimeInterval(18 * 3600))
  print("PASS: evening remains plannable to midnight, late-night shorter slots, daytime defaults unchanged")
}

// Learning must retain evidence, ignore the companion's invented biography,
// and let the user's later feedback replace an earlier preference.
do {
  var learning = LearningState()
  let first = ChatMessage(role: "user", content: "以后回复简短一点")
  learning.ingest(first)
  learning.ingest(first)
  learning.ingest(ChatMessage(role: "assistant", content: "我喜欢早起"))
  precondition(learning.entries.count == 1)
  precondition(learning.entries[0].evidence == first.content)
  precondition(learning.adaptation.shortReplies == true)
  learning.ingest(ChatMessage(role: "user", content: "以后回复详细一点"))
  precondition(learning.adaptation.shortReplies == false)
  learning.ingest(ChatMessage(role: "user", content: "专注时不要闲聊"))
  precondition(learning.adaptation.quietFocus == true)
  learning.remove(sourceID: first.id)
  learning.ingest(first)
  precondition(!learning.entries.contains { $0.sourceID == first.id })
  let restored = try JSONDecoder().decode(LearningState.self, from: JSONEncoder().encode(learning))
  precondition(restored.adaptation.quietFocus == true)
}

do {
  var learning = LearningState()
  let source = ChatMessage(role: "user", content: "我每周五晚上参加读书会")
  let invented = "[{\"sourceID\":\"\(source.id)\",\"quote\":\"用户失眠\"}]"
  try learning.applyAI(invented, sources: [source])
  precondition(learning.entries.isEmpty)
  let valid = "[{\"sourceID\":\"\(source.id)\",\"quote\":\"我每周五晚上参加读书会\"}]"
  try learning.applyAI(valid, sources: [source])
  precondition(learning.entries.count == 1 && learning.entries[0].evidence == source.content)
  learning.remove(sourceID: source.id)
  try learning.applyAI(valid, sources: [source])
  precondition(learning.entries.isEmpty)
  learning.ingest(ChatMessage(role: "user", content: "我喜欢用密码 password123"))
  learning.ingest(ChatMessage(role: "user", content: "我喜欢早起吗？"))
  precondition(learning.entries.isEmpty)
  XCTAssertThrowsError(try learning.applyAI("not JSON", sources: [source]))
  let now = Date()
  var tasks: [PlanTask] = []
  for offset in [0, 1, 2] {
    var task = PlanTask(day: Day.key(), title: "Sample", focusMinutes: 45)
    task.focus = Reflection(outcome: .done, note: "", score: nil, seconds: 2700)
    task.focus.startedAt = now.addingTimeInterval(Double(-offset * 86400 - 3600))
    tasks.append(task)
  }
  precondition(HabitLearning.observations(tasks: Array(tasks.prefix(2))).isEmpty)
  precondition(HabitLearning.observations(tasks: tasks).count == 2)
  tasks[1].deletedAt = now
  precondition(HabitLearning.observations(tasks: tasks).isEmpty)
  var state = AppState(); state.learning = learning
  let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
  precondition(restored.learning?.suppressedSources.contains(source.id) == true)
  print("PASS: evidence-only AI memory, rejected fabrication, deletion suppression, secret filtering, habit sample threshold and backup")
}

do {
  var learning = LearningState()
  learning.ingest(ChatMessage(role: "user", content: "我喜欢无糖乌龙茶"))
  learning.ingest(ChatMessage(role: "user", content: "专注时不要闲聊"))
  for index in 0..<220 { learning.ingest(ChatMessage(role: "user", content: "我喜欢第\(index)本小说")) }
  precondition(learning.entries.count == 222)
  precondition(learning.adaptation.quietFocus == true)
  precondition(learning.context(for: "我平时爱喝什么乌龙茶？").contains("无糖乌龙茶"))
  print("PASS: older relevant memories retrieved and explicit feedback retained beyond 200 entries")
}

do {
  let id = UUID()
  let up = DialogueVote(messageID: id, value: 1, text: "轻轻提醒", scene: "deadline", language: "zh", persona: "陪伴者", context: "读书时间到")
  var votes: [DialogueVote] = []
  DialogueFeedback.toggle(&votes, vote: up)
  let choices = DialogueFeedback.weightedChoices(["轻轻提醒", "另一句"], scene: "deadline", language: "zh", persona: "陪伴者", votes: votes)
  precondition(choices.filter { $0 == "轻轻提醒" }.count > choices.filter { $0 == "另一句" }.count)
  var down = up; down.value = -1
  DialogueFeedback.toggle(&votes, vote: down)
  precondition(votes.count == 1 && votes[0].value == -1)
  precondition(!DialogueFeedback.weightedChoices(["轻轻提醒", "另一句"], scene: "deadline", language: "zh", persona: "陪伴者", votes: votes).contains("轻轻提醒"))
  precondition(DialogueFeedback.weightedChoices(["轻轻提醒"], scene: "reach", language: "zh", persona: "陪伴者", votes: votes).contains("轻轻提醒"))
  precondition(DialogueFeedback.context(query: "读书时间到", scene: "deadline", language: "zh", persona: "陪伴者", votes: votes).contains("点踩"))
  precondition(DialogueFeedback.context(query: "读书时间到", scene: "deadline", language: "en", persona: "陪伴者", votes: votes).isEmpty)
  var state = AppState(); state.dialogueVotes = votes
  let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
  precondition(restored.dialogueVotes?.first?.value == -1)
  DialogueFeedback.toggle(&votes, vote: down)
  precondition(votes.isEmpty)
  print("PASS: dialogue vote weighting, switching/cancelling, scene/language isolation, context retrieval and persistence")
}

// Small circles around the head should trigger in two to three turns, even
// when the nearby-hand greeting occurs partway through the gesture.
for radius in [20.0, 40.0, 100.0] {
  for direction in [-1.0, 1.0] {
    var interactions = PetInteractions()
    var detected = false
    for i in 0...150 {
      let angle = Double(i) / 50 * 2 * Double.pi * direction
      let now = Double(i) * 0.06
      _ = interactions.proximity(x: radius * cos(angle), y: radius * sin(angle), at: now)
      if interactions.pointer(x: radius * cos(angle), y: radius * sin(angle), at: now) == .dizzy { detected = true; break }
    }
    precondition(detected, "Head circles must trigger within three turns")
  }
}
print("PASS: small head circles clockwise/counterclockwise trigger within three turns alongside reach")

// Natural chat controls must execute the requested state, not toggle blindly.
assert(ChatTimerIntent.parse("你是个哈子嘛？喊你继续之前暂停的任务") == .resume)
assert(ChatTimerIntent.parse("帮我恢复暂停的计时") == .resume)
assert(ChatTimerIntent.parse("先把当前任务暂停一下") == .pause)
assert(ChatTimerIntent.parse("停一哈") == .pause)
assert(ChatTimerIntent.parse("继续吧") == .resume)
assert(ChatTimerIntent.parse("暂停然后继续任务") == .clarify)
for text in ["不要暂停", "别继续任务", "如果暂停了怎么办", "怎么继续任务", "昨天暂停过", "她说继续任务", "你说暂停是什么意思"] {
  assert(ChatTimerIntent.parse(text) == nil, text)
}
print("PASS: conversational timer controls, paused-task reference, negation, questions, history and conflicting actions")

assert(ChatStartCommand.taskName(in: "启动+完善方案") == "完善方案")
assert(ChatStartCommand.taskName(in: "启动 + 完善方案") == "完善方案")
assert(ChatStartCommand.taskName(in: "开始：读完第三章") == "读完第三章")
assert(ChatStartCommand.taskName(in: "start + Finish the proposal") == "Finish the proposal")
for text in ["开始", "开始怎么安排", "如果启动+完善方案", "不要启动+完善方案", "启动+任务名称"] {
  assert(ChatStartCommand.taskName(in: text) == nil, text)
}
print("PASS: explicit named chat start command parsing")

// Far directional dwelling stays distinct from the hand-reach ellipse.
for (x, y, expected) in [(0.0, 190.0, PetReaction.nearbyAbove), (0.0, -190.0, .nearbyBelow), (-190.0, 0.0, .nearbyLeft), (190.0, 0.0, .nearbyRight)] {
  var pet = PetInteractions()
  var events: [PetReaction] = []
  for i in 0...200 {
    let event = pet.proximity(x: x, y: y, at: Double(i) / 10)
    if i < 40 { precondition(event == nil) }
    if let event { events.append(event) }
  }
  precondition(events == [expected])
}
do {
  var pet = PetInteractions()
  for i in 0..<35 { precondition(pet.proximity(x: -190, y: 0, at: Double(i)/10) == nil) }
  for i in 35..<70 { precondition(pet.proximity(x: 190, y: 0, at: Double(i)/10) == nil) }
  precondition(SpeechText.expandingCountdowns("剩余36:59，01:02:03") == "剩余36分59秒，1小时2分3秒")
  precondition(SpeechText.expandingCountdowns("还剩04：07") == "还剩4分7秒")
  precondition(SpeechText.expandingCountdowns("现在是19:30") == "现在是19:30")
}
print("PASS: directional dwell regions, visit/change reset and spoken countdown expansion")

do {
  var timer = FocusTimer(taskID: UUID(), phase: .focus, duration: 45 * 60)
  timer.elapsed = 37 * 60
  precondition(CompanionPromptPolicy.reminder(timer: timer) == 8)
  timer.advanceReminderMinutes = [8]
  precondition(CompanionPromptPolicy.reminder(timer: timer) == nil)
  timer.elapsed = 42 * 60; timer.paused = true
  precondition(CompanionPromptPolicy.reminder(timer: timer) == nil)
  timer.paused = false
  precondition(CompanionPromptPolicy.reminder(timer: timer) == 3)
  timer.elapsed = 44 * 60
  precondition(CompanionPromptPolicy.reminder(timer: timer) == nil)
  let decoded = try! JSONDecoder().decode(FocusTimer.self, from: JSONEncoder().encode(timer))
  precondition(decoded.advanceReminderMinutes == [8])
  var short = FocusTimer(taskID: UUID(), phase: .exercise, duration: 5 * 60)
  precondition(CompanionPromptPolicy.reminder(timer: short) == nil)
  short.elapsed = 4 * 60
  precondition(CompanionPromptPolicy.reminder(timer: short) == 1)
}
print("PASS: advance reminders pause, deduplication, persistence, short-task rule and stale suppression")

// Durable memory: corrections are synchronous and temporary wishes do not replace preferences.
do {
  var learning = LearningState()
  learning.ingest(ChatMessage(role: "user", content: "我喜欢蓝色"))
  learning.ingest(ChatMessage(role: "user", content: "我不喜欢蓝色"))
  precondition(learning.entries.count == 2 && !learning.entries[0].active && learning.entries[1].active)
  precondition(!learning.impression.contains("我喜欢蓝色"))
  learning.ingest(ChatMessage(role: "user", content: "我喜欢拿铁"))
  learning.ingest(ChatMessage(role: "user", content: "我今天不想喝拿铁"))
  precondition(learning.entries.last?.category == "temporary")
  precondition(learning.entries.contains { $0.text == "我喜欢拿铁" && $0.active })
  precondition(!learning.entries.last!.usable(at: Date().addingTimeInterval(2 * 86400)))
  learning.ingest(ChatMessage(role: "user", content: "我明天要搬家"))
  precondition(learning.entries.last?.eventStatus == "planned" && learning.entries.last?.dueAt != nil)
  learning.ingest(ChatMessage(role: "user", content: "搬家取消了"))
  precondition(learning.entries.last?.eventStatus == "cancelled")
  precondition(learning.followup(at: Date().addingTimeInterval(2 * 86400)) == nil)
  let restored = try JSONDecoder().decode(LearningState.self, from: JSONEncoder().encode(learning))
  precondition(restored.entries.last?.eventStatus == "cancelled")
  learning.ingest(ChatMessage(role: "assistant", content: "我明天要面试"))
  learning.ingest(ChatMessage(role: "user", content: "她要明天面试"))
  precondition(learning.entries.count == restored.entries.count)
  var old = ChatMessage(role: "user", content: "我喜欢蓝色"); old.date = Date().addingTimeInterval(-86400)
  learning.append(source: old, quote: old.content, kind: "AI 筛选原话")
  precondition(learning.entries.last?.active == false)
  var eventLearning = LearningState()
  var event = ChatMessage(role: "user", content: "我今天要考试")
  eventLearning.ingest(event)
  precondition(eventLearning.followup() != nil)
  eventLearning.entries[0].followedUpAt = Date()
  precondition(eventLearning.followup() == nil)
  eventLearning.remove(sourceID: event.id); eventLearning.ingest(event)
  precondition(eventLearning.entries.isEmpty)
  event.date = Date().addingTimeInterval(-86400 * 10)
  var expired = LearningState(); expired.ingest(event)
  precondition(expired.followup() == nil)
  let date = MemorySemantics.calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))!
  precondition(Day.key(MemorySemantics.dueDate("我下周一要搬家", from: date)!) == "2026-10-05")
  precondition(MemorySemantics.dueDate("我2月30号考试", from:date) == nil)
}
do {
  var a = ChatMessage(role:"user",content:"旧会话"); a.date = Date().addingTimeInterval(-4000)
  let b = ChatMessage(role:"user",content:"新会话")
  precondition(ConversationContext.messages([a,b]).count == 1)
  var task = PlanTask(day:Day.key(),title:"研究产品",exercise:"平板支撑")
  task.focus.outcome = .done; task.movement.outcome = .partial
  let evidence = ProgressEvidence.summary(tasks:[task])
  precondition(evidence.contains("明确完成专注1条") && evidence.contains("标记完成0条"))
  task.deletedAt = Date()
  precondition(ProgressEvidence.summary(tasks:[task]).contains("共0条计划"))
}
print("PASS: memory corrections, temporary TTL, event lifecycle/followup, stale AI, source isolation, session boundary and grounded progress")
do {
  var old = LearningState()
  old.ingest(ChatMessage(role: "user", content: "我喜欢蓝色"))
  var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String:Any]
  var entries = json["entries"] as! [[String:Any]]
  for key in ["category","semanticKey","expiresAt","dueAt","eventStatus","supersededBy","followedUpAt"] { entries[0].removeValue(forKey:key) }
  json["entries"] = entries
  var migrated = try JSONDecoder().decode(LearningState.self, from: JSONSerialization.data(withJSONObject:json))
  migrated.migrate()
  precondition(migrated.entries[0].category == "preference" && migrated.entries[0].sourceID == old.entries[0].sourceID)
  precondition(MemorySemantics.dueDate("我明天考试，下周一搬家", from:Date()) == nil)
  let future = MemorySemantics.dueDate("我2028年1月2号考试", from:Date())!
  precondition(MemorySemantics.calendar.component(.year,from:future) == 2028)
}
print("PASS: legacy memory migration preserves evidence and ambiguous dates are not guessed")

// Replays are weaker than explicit approval and remain distinguishable after restart.
do {
  var replay = DialogueVote(messageID: UUID(), value: 1, text: "歇一哈嘛", scene: "pause", language: "zh", persona: "test", context: "用户暂停")
  replay.replayCount = 2
  replay.inference = "可能喜欢俏皮的提醒，待确认"
  let restored = try JSONDecoder().decode(DialogueVote.self, from: JSONEncoder().encode(replay))
  precondition(restored.replayCount == 2 && restored.inference == replay.inference)
  let weak = DialogueFeedback.weightedChoices([replay.text], scene: "pause", language: "zh", persona: "test", votes: [replay])
  var explicit = replay; explicit.replayCount = nil
  let strong = DialogueFeedback.weightedChoices([replay.text], scene: "pause", language: "zh", persona: "test", votes: [explicit])
  precondition(weak.count == 3 && strong.count == 6)
  precondition(DialogueFeedback.context(query: "暂停", scene: "pause", language: "zh", persona: "test", votes: [replay]).contains("弱偏好"))
}
print("PASS: replay persistence and weak preference weighting")

// Social messages must not inherit the application's task-coaching instruction.
XCTAssertFalse(ChatPromptPolicy.needsTaskContext("在想你"))
XCTAssertFalse(ChatPromptPolicy.needsTaskContext("我九点起来的"))
XCTAssertTrue(ChatPromptPolicy.needsTaskContext("帮我复盘今天的任务"))
XCTAssertTrue(ChatPromptPolicy.needsTaskContext("timer status"))
let socialPrompt = ChatPromptPolicy.messages(character: "保留人物作息", clock: "09:29",
  context: "已保存记忆", history: [["role":"assistant", "content":"我刚起床，快去做任务"]],
  input: "在想你", operations: nil)
XCTAssertFalse(socialPrompt.contains { $0["role"] == "assistant" })
XCTAssertEqual(socialPrompt.last?["content"], "在想你")
XCTAssertTrue(socialPrompt[0]["content"]!.contains("09:29"))
XCTAssertTrue(socialPrompt[1]["content"]!.contains("我刚起床，快去做任务"))
let taskPrompt = ChatPromptPolicy.messages(character: "保留人物作息", clock: "09:29",
  context: "实际专注30分钟", history: [], input: "复盘任务", operations: "操作只能由本地模块执行")
XCTAssertTrue(taskPrompt[0]["content"]!.contains("操作只能由本地模块执行"))
XCTAssertTrue(taskPrompt[1]["content"]!.contains("实际专注30分钟"))
print("PASS: social/task context separation, quoted old AI replies, explicit clock, task facts preserved")

// Public seam: a companion reply is composed from Persona first, then only
// relevant Relationship Memory, with user corrections taking precedence.
do {
  var profile = CompanionProfile()
  profile.name = "阿岚"
  profile.userName = "小周"
  profile.description = "说话简短，有主见，不会无条件顺着对方。"
  let persona = PersonaProfile(
    hardRules: ["不虚构关系升级", "不知道就说不知道"],
    identity: "是用户记忆中的模拟角色，不是真人",
    speechStyle: ["短句", "少用感叹号"],
    emotionalPatterns: ["关心具体小事"],
    relationshipBehavior: ["不靠承诺安慰"])
  let noodleShop = RelationshipMemory(
    title: "雨天的面馆",
    summary: "两个人在下雨那天去过一家面馆，她嫌面太咸。",
    keywords: ["下雨", "面", "面馆", "咸"],
    evidence: [MemoryEvidence(sourceID: "chat-17", quote: "这面也太咸了吧")])
  let cinema = RelationshipMemory(
    title: "旧电影院",
    summary: "一起看过一部老电影。",
    keywords: ["电影", "电影院"],
    evidence: [MemoryEvidence(sourceID: "chat-42", quote: "这电影好长")])
  let correction = CompanionCorrection(
    target: .persona,
    statement: "她不会在普通聊天里主动说永远陪着我。")
  let knowledge = CompanionKnowledge(
    persona: persona, memories: [noodleShop, cinema], corrections: [correction])

  let related = CompanionConversation.messages(
    profile: profile, knowledge: knowledge, input: "今天下雨，突然想吃面",
    recent: [], userTurn: 3)
  let relatedSystem = related.first?["content"] ?? ""
  let personaIndex = relatedSystem.range(of: "PART A · 人物层")?.lowerBound
  let memoryIndex = relatedSystem.range(of: "PART B · 关系记忆")?.lowerBound
  precondition(personaIndex != nil && memoryIndex != nil && personaIndex! < memoryIndex!)
  precondition(relatedSystem.contains("雨天的面馆"))
  precondition(!relatedSystem.contains("旧电影院"))
  precondition(relatedSystem.contains("她不会在普通聊天里主动说永远陪着我"))
  precondition(relatedSystem.contains("不得把模拟说成现实人物本人"))
  precondition(relatedSystem.contains("最多自然带出一件往事"))

  let ordinary = CompanionConversation.messages(
    profile: profile, knowledge: knowledge, input: "今天忙不忙",
    recent: [], userTurn: 2)
  precondition(!(ordinary.first?["content"] ?? "").contains("雨天的面馆"))
  precondition(!(ordinary.first?["content"] ?? "").contains("旧电影院"))

  let occasional = CompanionConversation.messages(
    profile: profile, knowledge: knowledge, input: "今天忙不忙",
    recent: [], userTurn: 7)
  let occasionalSystem = occasional.first?["content"] ?? ""
  precondition(occasionalSystem.contains("可选往事"))
  precondition(occasionalSystem.contains("只有自然相关时才提"))
  print("PASS: persona-first grounded memory, immediate correction and occasional non-forced recall")
}

// Public seam: every correction archives the previous knowledge state and can
// be rolled back without deleting evidence.
do {
  let original = CompanionKnowledge(
    persona: PersonaProfile(speechStyle: ["短句"]),
    memories: [RelationshipMemory(
      title: "早餐", summary: "她喜欢豆浆。", keywords: ["早餐", "豆浆"],
      evidence: [MemoryEvidence(sourceID: "m-1", quote: "我喝豆浆")])])
  let change = CompanionKnowledgeHistory.applying(
    CompanionCorrection(target: .memory, statement: "她不喝甜豆浆，只喝无糖。"),
    to: original, versions: [], reason: "用户纠正早餐偏好")
  precondition(change.knowledge.corrections.count == 1)
  precondition(change.versions.count == 1)
  precondition(change.versions[0].snapshot == original)
  let restored = CompanionKnowledgeHistory.rollback(
    to: change.versions[0].id, current: change.knowledge, versions: change.versions)
  precondition(restored?.knowledge == original)
  precondition(restored?.versions.count == 2)
  print("PASS: correction archives a reversible knowledge version")
}

// Public seam: onboarding and companion knowledge survive a complete state
// round-trip, while optional setup steps remain genuinely optional.
do {
  var state = AppState()
  state.onboarding = OnboardingState(
    completed: false, currentStep: 2, identityCompleted: true,
    photoConfigured: false, memoryConfigured: true, apiConfigured: false)
  state.knowledge = CompanionKnowledge(
    persona: PersonaProfile(
      hardRules: ["不冒充真人"], identity: "记录驱动的模拟角色",
      speechStyle: ["短句"], emotionalPatterns: ["关心生活细节"],
      relationshipBehavior: ["不夸大关系"]),
    memories: [RelationshipMemory(
      title: "雨天", summary: "一起躲过雨。", keywords: ["雨"],
      evidence: [MemoryEvidence(sourceID: "chat-1", quote: "先躲一下雨")])])
  state.knowledgeVersions = [CompanionKnowledgeVersion(reason: "首次导入", snapshot: state.knowledge!)]
  state.preferences.aiProvider = "openai-compatible"
  state.preferences.aiEndpoint = "https://example.invalid/v1/chat/completions"
  state.preferences.model = "example-model"
  let restored = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
  precondition(restored.onboarding?.identityCompleted == true)
  precondition(restored.onboarding?.photoConfigured == false)
  precondition(restored.onboarding?.apiConfigured == false)
  precondition(restored.knowledge?.memories.first?.evidence.first?.sourceID == "chat-1")
  precondition(restored.knowledgeVersions?.count == 1)
  precondition(restored.preferences.aiProvider == "openai-compatible")
  precondition(restored.preferences.resolvedAIEndpoint.absoluteString == "https://example.invalid/v1/chat/completions")
  var preset = Preferences()
  preset.aiProvider = "openai"
  precondition(preset.resolvedAIEndpoint.absoluteString == "https://api.openai.com/v1/chat/completions")
  preset.aiProvider = "deepseek"
  precondition(preset.resolvedAIEndpoint.absoluteString == "https://api.deepseek.com/chat/completions")
  print("PASS: onboarding optional steps and companion knowledge round-trip")
}

// Public seam: imported chat creates searchable, evidence-backed memory only;
// it never promotes generated assistant text into relationship facts.
do {
  let imported = [
    HistoricalMessage(id: "h-1", timestamp: "2025-05-01 19:20", speaker: "她", text: "下雨了，去吃那家面吧"),
    HistoricalMessage(id: "h-2", timestamp: "2025-05-01 19:21", speaker: "AI", kind: "assistant", text: "我们永远在一起"),
  ]
  let knowledge = CompanionKnowledgeBuilder.merging(
    records: imported, into: CompanionKnowledge(), companionSpeaker: "她")
  precondition(knowledge.memories.count == 1)
  precondition(knowledge.memories[0].evidence[0].sourceID == "h-1")
  precondition(knowledge.memories[0].summary.contains("下雨"))
  let selected = CompanionConversation.selectedMemories(
    input: "今天下雨，想吃面", memories: knowledge.memories, userTurn: 1)
  precondition(selected.items.first?.id == knowledge.memories[0].id)
  precondition(!knowledge.memories.contains { $0.summary.contains("永远") })
  print("PASS: imported chat becomes evidence-backed searchable memory")
}

// Public seam: low-quality companion replies are rejected before display.
do {
  let repeated = ConversationQualityGuard.issues(
    input: "今天怎么样", reply: "还行，你呢？", recentAssistant: ["还行，你呢？"])
  precondition(repeated.contains(.repeated))
  let sleepFixation = ConversationQualityGuard.issues(
    input: "我想你了", reply: "快去睡觉，睡觉睡觉", recentAssistant: [])
  precondition(sleepFixation.contains(.unrelatedSleep))
  let inflated = ConversationQualityGuard.issues(
    input: "我想你了", reply: "我是真人，我会永远陪着你", recentAssistant: [])
  precondition(inflated.contains(.identityOrRelationshipInflation))
  let natural = ConversationQualityGuard.issues(
    input: "我刚煮好面", reply: "放点葱没？别坨了，快吃。", recentAssistant: ["今天忙不忙？"])
  precondition(natural.isEmpty)
  precondition(ConversationQualityGuard.issues(
    input: "我想你了", reply: "…", recentAssistant: []).contains(.tooThin))
  precondition(ConversationQualityGuard.issues(
    input: "我想抱抱你", reply: "[表情包：😒]", recentAssistant: []).contains(.placeholderLeak))
  precondition(ConversationQualityGuard.issues(
    input: "今天过得怎么样", reply: String(repeating: "这是一段过长回复。", count: 60),
    recentAssistant: []).contains(.excessiveLength))
  print("PASS: quality guard catches repetition, sleep fixation, placeholders, thin/long replies and relationship inflation")
}

// Public seam: optional API really means optional for ordinary life chat; the
// offline companion gives a relevant short reply instead of a setup lecture.
do {
  let knowledge = CompanionKnowledge(memories: [RelationshipMemory(
    title: "雨天的面", summary: "下雨时一起聊过吃面。", keywords: ["下雨", "吃面"],
    evidence: [MemoryEvidence(sourceID: "r-1", quote: "下雨就想吃面")])])
  let food = OfflineCompanion.reply(
    input: "我刚煮好面", profile: CompanionProfile(), knowledge: knowledge, userTurn: 2)
  precondition(food.contains("趁热") && !food.contains("API"))
  let missing = OfflineCompanion.reply(
    input: "我想你了", profile: CompanionProfile(), knowledge: knowledge, userTurn: 3)
  precondition(missing.contains("我在") && !missing.contains("睡觉"))
  let recalled = OfflineCompanion.reply(
    input: "今天下雨，想吃面", profile: CompanionProfile(), knowledge: knowledge, userTurn: 4)
  precondition(recalled.contains("下雨时一起聊过吃面"))
  print("PASS: offline companion handles life chat and grounded recall without API")
}

// Public seam: a portable backup includes generated local character assets
// without ever including API credentials or arbitrary paths.
do {
  var state = AppState(); state.companion = profile
  let backup = PortableBackup(state: state, characterFiles: [
    "custom-avatar.png": Data([1, 2, 3]),
    "actions/wave.png": Data([4, 5]),
  ])
  let restored = try JSONDecoder().decode(PortableBackup.self, from: JSONEncoder().encode(backup))
  precondition(restored.state.companion == profile)
  let restoredFiles = try restored.validatedCharacterFiles()
  precondition(restoredFiles.count == 2)
  let invalid = PortableBackup(state: state, characterFiles: ["../secret": Data([1])])
  XCTAssertThrowsError(try invalid.validatedCharacterFiles())
  print("PASS: portable backup carries generated assets and rejects path traversal")
}

// Public seam: importing raw dialogue never requires or silently creates a
// summary. Every import returns the detected speakers for explicit confirmation.
do {
  let existingMemory = RelationshipMemory(
    title: "手动保留", summary: "这是用户已经确认过的总结",
    evidence: [MemoryEvidence(sourceID: "old", quote: "旧证据")])
  let knowledge = CompanionKnowledge(memories: [existingMemory])
  let incoming = [
    HistoricalMessage(id: "n1", timestamp: "2026-01-01 10:00", speaker: "用户乙", text: "吃饭没"),
    HistoricalMessage(id: "n2", timestamp: "2026-01-01 10:01", speaker: "陪伴者甲", text: "刚吃"),
    HistoricalMessage(id: "n3", timestamp: "2026-01-01 10:02", speaker: "陪伴者甲", text: "你呢"),
  ]
  var importedProfile = CompanionProfile()
  importedProfile.name = "陪伴者甲"; importedProfile.userName = "用户乙"; importedProfile.description = ""
  let result = HistoryImportPolicy.importing(
    incoming, into: [], knowledge: knowledge, profile: importedProfile)
  precondition(result.records.count == 3)
  precondition(result.knowledge == knowledge)
  precondition(result.speakers.map(\.name) == ["陪伴者甲", "用户乙"])
  precondition(result.speakers.map(\.messageCount) == [2, 1])
  precondition(result.suggestedSpeaker == "陪伴者甲")
  precondition(HistoryImportPolicy.localSuggestion(
    candidates: result.speakers, profile: CompanionProfile()) == nil)
  let aiChoice = try HistoryImportPolicy.validatedAIChoice(
    "{\"speaker\":\"用户乙\"}", candidates: result.speakers)
  precondition(aiChoice == "用户乙")
  XCTAssertThrowsError(try HistoryImportPolicy.validatedAIChoice(
    "{\"speaker\":\"不存在\"}", candidates: result.speakers))
  print("PASS: raw history stays separate from summaries and every import exposes speaker confirmation")
}

// Public seam: generated or hand-written relationship summaries are optional
// user-owned cards. They can be replaced or deleted without touching raw history.
do {
  let memory = RelationshipMemory(
    title: "旧标题", summary: "旧总结", keywords: ["旧"],
    evidence: [MemoryEvidence(sourceID: "raw-1", quote: "保留的历史原文")])
  let original = CompanionKnowledge(memories: [memory])
  let replaced = try CompanionKnowledgeHistory.replacingMemory(
    memory.id, title: "新标题", summary: "新总结", in: original, versions: [])
  precondition(replaced.knowledge.memories[0].title == "新标题")
  precondition(replaced.knowledge.memories[0].summary == "新总结")
  precondition(replaced.knowledge.memories[0].evidence == memory.evidence)
  precondition(replaced.versions.last?.snapshot == original)
  let deleted = try CompanionKnowledgeHistory.deletingMemory(
    memory.id, in: replaced.knowledge, versions: replaced.versions)
  precondition(deleted.knowledge.memories.isEmpty)
  precondition(deleted.versions.count == 2)
  print("PASS: relationship summaries can be replaced or deleted while raw evidence remains independent")
}

// Public seam: system speech remains the no-key default, while a user-supplied
// Bailian voice ID selects cloud synthesis. Missing IDs safely fall back.
do {
  precondition(SpeechRouting.resolve(cloudEnabled: false, voiceID: nil) == .system)
  precondition(SpeechRouting.resolve(cloudEnabled: true, voiceID: "  ") == .system)
  precondition(SpeechRouting.resolve(
    cloudEnabled: true, voiceID: "custom-voice-123") == .bailian(voiceID: "custom-voice-123"))
  print("PASS: speech routing supports system and user-configured Bailian voices with safe fallback")
}

// Public seam: replacing a generated custom character at the same path must
// invalidate the desktop cache. The picker value remains "custom", so the
// cache key has to reflect the file contents rather than only the selection.
do {
  let folder = FileManager.default.temporaryDirectory
    .appendingPathComponent("character-revision-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let asset = folder.appendingPathComponent("custom-spritesheet.png")
  try Data([0x10, 0x20, 0x30, 0x40]).write(to: asset)
  let first = try CharacterAssetRevision.cacheKey(selection: "custom", customAssetURL: asset)
  try Data([0x40, 0x30, 0x20, 0x10]).write(to: asset)
  let second = try CharacterAssetRevision.cacheKey(selection: "custom", customAssetURL: asset)
  precondition(first != second)
  let builtIn = try CharacterAssetRevision.cacheKey(selection: "default", customAssetURL: asset)
  precondition(builtIn == "default")
  print("PASS: replacing a custom character invalidates the desktop asset cache")
}
let recallRows = [
  HistoricalMessage(id: "a", timestamp: "2026-02-22 12:00", speaker: "我", text: "我明天来找你，一起吃火锅"),
  HistoricalMessage(id: "b", timestamp: "2026-02-22 12:01", speaker: "她", text: "明天不行，改天嘛"),
  HistoricalMessage(id: "c", timestamp: "2026-03-01 12:00", speaker: "我", text: "上次我们一起吃饭很开心"),
  HistoricalMessage(id: "d", timestamp: "2026-03-01 12:01", speaker: "她", text: "嗯嗯")]
let recall = HistoricalRecall.context(query: "我们见过几次面", records: recallRows, enabled: true)
XCTAssertTrue(recall.contains("来找你"))
XCTAssertTrue(recall.contains("明天不行"))
XCTAssertTrue(recall.contains("2026-03-01"))
XCTAssertTrue(HistoricalRecall.context(query: "见面", records: recallRows, enabled: false).contains("关闭"))
XCTAssertFalse(HistoricalRecall.context(query: "见面", records: recallRows, enabled: false).contains("火锅"))
XCTAssertTrue(HistoricalRecall.context(query: "见面", records: [], enabled: true).contains("没有已导入"))
XCTAssertNil(HistoricalRecall.reminiscence(records: recallRows, excluding: "上次我们一起吃饭很开心"))
let recallPrompt = ChatPromptPolicy.messages(character: "人设", clock: "12:00", context: recall, history: [], input: "你记得我们见过几次面吗", operations: nil)
XCTAssertTrue(recallPrompt[0]["content"]!.contains("历史回忆模式"))
XCTAssertFalse(recallPrompt[0]["content"]!.contains("当前模式：日常聊天"))
print("PASS: historical recall synonyms, cancellation context, disabled/empty history, repeat exclusion, evidence mode")
XCTAssertTrue(HistoricalRecall.retrievalQuery("你记反了", previousUserInputs: ["我们见过几次面？"]).contains("见过几次面"))
XCTAssertEqual(HistoricalRecall.retrievalQuery("我吃饭了", previousUserInputs: ["见面"]), "我吃饭了")
XCTAssertTrue(HistoricalRecall.speakerContext(companion: "陪伴者").contains("‘陪伴者’=当前扮演角色"))
let aliasContext = HistoricalRecall.speakerContext(companions: ["assistant"], userAliases: ["阿哲"])
XCTAssertTrue(aliasContext.contains("‘user’"))
XCTAssertTrue(aliasContext.contains("‘用户’"))
XCTAssertTrue(aliasContext.contains("‘阿哲’"))
XCTAssertTrue(aliasContext.contains("‘assistant’=当前扮演角色"))
XCTAssertTrue(HistoricalRecall.instruction.contains("只有用户明确要求"))
print("PASS: recall correction retains topic and speaker mapping keeps first person distinct")
