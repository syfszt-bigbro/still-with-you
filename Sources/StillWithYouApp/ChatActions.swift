import Foundation
import StillWithYouCore

extension AppModel {
  func handleChatTimerControl(_ input: String) -> Bool {
    guard let intent = ChatTimerIntent.parse(input) else { return false }
    guard intent != .clarify else {
      appendBasicReply("你是要暂停，还是继续当前任务？请确认一下。"); return true
    }
    guard let timer = state.timer else {
      if intent == .resume { _ = handleChatStart("启动任务") }
      else { appendBasicReply("当前没有正在计时的任务，不需要暂停。") }
      return true
    }
    guard !timer.awaitingReflection else {
      appendBasicReply("当前任务已经到期，请先填写反馈，再启动下一项任务。"); return true
    }
    let shouldPause = intent == .pause
    if timer.paused != shouldPause { togglePause(announce: false) }
    appendBasicReply((shouldPause ? "已暂停。" : "已继续。") + liveTimerDescription)
    return true
  }

  var chatStartChoices: [PlanTask] {
    chatStartIDs.compactMap { id in state.tasks.first { $0.id == id && canChatStart($0) } }
  }
  func canChatStart(_ task: PlanTask) -> Bool {
    task.day == Day.key() && !task.cancelled && task.deletedAt == nil && task.focus.outcome == .pending && !task.isExpired(activeTaskID: state.timer?.taskID)
  }
  func startFromChat(_ id: UUID) {
    guard let task = state.tasks.first(where: { $0.id == id }), canChatStart(task) else {
      chatStartIDs = []; appendBasicReply("这项任务已不可启动，请重新选择今天的未完成任务。"); return
    }
    guard state.timer == nil else {
      appendBasicReply("当前还有「\(activeTask?.title ?? "任务")」的计时或反馈待处理。要暂停、继续，还是结束并记录？我不会替换它。"); return
    }
    start(task, phase: .focus, announce: false)
    guard state.timer?.taskID == task.id else { appendBasicReply(notice); return }
    chatStartIDs = []
    appendBasicReply("\(userName)，「\(task.title)」已开始专注，\(task.focusMinutes) 分钟。倒计时已经启动。")
  }
  /// Only current user input can authorize an action; generated replies and
  /// imported history never execute commands.
  func handleChatStart(_ input: String) -> Bool {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: .punctuationCharacters).lowercased()
    if !chatStartIDs.isEmpty {
      if ["取消", "算了", "不用了", "cancel"].contains(text) {
        chatStartIDs = []; appendBasicReply("好，这次不启动。"); return true
      }
      let choices = chatStartChoices
      if let task = choices.first(where: { $0.title.lowercased() == text }) {
        startFromChat(task.id); return true
      }
      let ordinals = ["第一个", "第二个", "第三个", "第四个", "第五个"]
      if let index = Int(text).map({ $0 - 1 }) ?? ordinals.firstIndex(of: text), choices.indices.contains(index) {
        startFromChat(choices[index].id); return true
      }
      if Self.isStartConfirmation(text) {
        if choices.count == 1 { startFromChat(choices[0].id) }
        else { appendBasicReply("请点选要启动的任务，或告诉我任务名称、序号。") }
        return true
      }
    }
    let command = text.contains("启动") || text.contains("开始") || text.contains("开启") || text.contains("开起来") || text.hasPrefix("start ")
    guard command else { return false }
    if ["不要", "别", "不想", "不启动", "不开始", "不开启", "如果", "假如", "昨天", "刚才", "怎么", "如何", "为什么", "don't", "how ", "if "].contains(where: text.contains) { return false }
    guard state.timer == nil else {
      appendBasicReply("当前还有「\(activeTask?.title ?? "任务")」的计时或反馈待处理。你想暂停、继续，还是结束并记录？"); return true
    }
    let candidates = state.tasks.filter { canChatStart($0) }
    if let requestedName = ChatStartCommand.taskName(in: input) {
      let normalizedName = requestedName.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
      let exactMatches = candidates.filter {
        $0.title.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation } == normalizedName
      }
      if exactMatches.count == 1 { startFromChat(exactMatches[0].id); return true }
      if exactMatches.count > 1 {
        appendBasicReply("今天有几项都叫「\(requestedName)」，请告诉我计划列表里的序号。"); return true
      }
      let partialMatches = candidates.filter {
        let title = $0.title.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
        return title.contains(normalizedName) || normalizedName.contains(title)
      }
      if partialMatches.count == 1 { startFromChat(partialMatches[0].id); return true }
      if partialMatches.count > 1 {
        appendBasicReply("我找到几项相近任务：\n" + partialMatches.enumerated().map { "\($0.offset + 1). \($0.element.title) · \($0.element.focusMinutes) 分钟" }.joined(separator: "\n")); return true
      }

      // A named command is itself permission to create and start a task. Keep
      // it in today's plan/statistics so the timer has a durable task record.
      let task = PlanTask(day: Day.key(), title: String(requestedName.prefix(120)), focusMinutes: 30,
        exerciseMinutes: 0, exercise: "")
      state.tasks.append(task)
      startFromChat(task.id)
      return true
    }
    let named = candidates.filter { text.contains($0.title.lowercased()) }
    if named.count == 1 {
      startFromChat(named[0].id); return true
    }
    if candidates.count == 1 { startFromChat(candidates[0].id); return true }
    chatStartIDs = candidates.map(\.id)
    if candidates.isEmpty {
      appendBasicReply("今天没有可启动的专注任务了。你想做什么、专注多少分钟？也可以在‘今天’页保存并启动一项新任务。")
    } else {
      appendBasicReply("要启动哪一项？可提前开始，请选择或回复序号：\n" + candidates.enumerated().map { "\($0.offset + 1). \($0.element.title) · \($0.element.focusMinutes) 分钟" }.joined(separator: "\n"))
    }
    return true
  }
}
