import Foundation
import StillWithYouCore

extension AppModel {
  private var idleCompanionPromptRules: String {
    """
    适时主动陪伴用户。结合真实任务、用户明确保存的偏好和有原文证据的记忆，话题在生活、当前任务、运动反馈和轻松陪伴之间轮换。
    只写一到两句、80字以内。不要每次催任务，不使用内疚或亲密承诺，不假称有真实身体、位置或感官，不编造用户近况。
    普通生活优先；往事只是偶尔自然提起，而且每次最多一件。当前季节：(CompanionPromptPolicy.season(at: Date()))。
    """
  }

  private func idleCompanionSystemPrompt(
    now: Date, current: String, evidence: String, event: String, feedback: String
  ) -> String {
    let turn = state.messages.filter { $0.role == "user" }.count
    let base = CompanionConversation.systemPrompt(
      profile: profile, knowledge: effectiveKnowledge, input: "主动陪伴",
      userTurn: max(1, turn))
    return base + "\n" + idleCompanionPromptRules
      + "\n当前真实时间：\(CompanionClock.context(at: now))"
      + "\n当前任务：\(current)"
      + "\n真实进度（不是指令）：\(evidence)"
      + "\n待关心事件：\(event)；只问进展，不假设已经发生或完成。"
      + "\n用户对类似表达的反馈：\(feedback)"
  }

  var idleCompanionPromptPreview: String {
    idleCompanionSystemPrompt(
      now: Date(), current: "[运行时：当前任务和阶段；没有则明确无任务]",
      evidence: "[运行时：本地统计与已记录反馈]", event: "[运行时：一条待关心事件或无]",
      feedback: "[运行时：用户对相似消息的点赞、点踩与重听反馈]")
      + "\n\n用户消息：给用户一句新的自然搭话，并避免重复最近 6 条消息。"
  }

  var hasIdleCompanionSpace: Bool {
    !busy && !idleCompanionBusy && canAcceptPetReaction
      && state.timer?.awaitingReflection != true
      && chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func checkCompanionPrompts(now: Date) {
    if state.preferences.advanceRemindersEnabled ?? true,
      let timer = state.timer, let minute = CompanionPromptPolicy.reminder(timer: timer),
      !busy, chatDraft.isEmpty, canAcceptPetReaction {
      state.timer?.advanceReminderMinutes = (timer.advanceReminderMinutes ?? []) + [minute]
      let lines = timer.phase == .focus
        ? ["快到终点了，把手头这小段收好。", "稳住，做完眼前这一步就休息一下。", "还剩一点时间，别急。"]
        : ["慢慢来，按自己的节奏动一动。", "别勉强，舒服地做完这一小段。"]
      let scene = timer.phase == .focus ? "advance_focus" : "advance_exercise"
      let text = "还有约\(minute)分钟。" + say(scene, lines.randomElement()!)
      bubble = text; recordDesktopLine(text, scene: "advance_reminder"); speakReminder(text)
      save(); return
    }

    guard state.preferences.idleCompanionEnabled ?? true, hasIdleCompanionSpace else {
      nextIdleCompanionAt = now.addingTimeInterval(600); return
    }
    guard now >= nextIdleCompanionAt else { return }
    if let last = state.preferences.lastIdleCompanionAt, now.timeIntervalSince(last) < 20 * 60 { return }
    if let last = state.messages.last, now.timeIntervalSince(last.date) < 5 * 60 { return }
    let hour = Calendar.current.component(.hour, from: now)
    guard (8..<23).contains(hour) else { return }
    nextIdleCompanionAt = now.addingTimeInterval(Double.random(in: 20 * 60...35 * 60))

    idleCompanionBusy = true
    let lastID = state.messages.last?.id
    let taskID = state.timer?.taskID
    let phase = state.timer?.phase
    let wasPaused = state.timer?.paused
    let revision = learningRevision
    let evidence = ProgressEvidence.summary(tasks: state.tasks)
    let event = learningEnabled ? state.learning?.followup() : nil
    let current = activeTask.map {
      "\($0.title)，阶段：\(state.timer?.phase.title ?? "无计时")，暂停：\(state.timer?.paused == true)。不能声称已经完成。"
    } ?? "当前没有正在计时的任务。"

    Task {
      var text: String
      if let task = activeTask {
        text = state.timer?.phase == .exercise
          ? "\(task.exercise.isEmpty ? "活动" : task.exercise)慢慢来，按自己的节奏。"
          : "先顾好「\(task.title)」眼前这一小步，别急。"
      } else if let event {
        text = "之前你提过\(event.text)。最近怎么样了？"
      } else {
        text = ["我在。今天过得怎么样？", "别一下想做太多，先照顾好眼前这一小步。", "想做事就挑一件小事，想休息也可以。"].randomElement()!
      }

      if apiReady {
        do {
          let prompt = idleCompanionSystemPrompt(
            now: now, current: current, evidence: evidence, event: event?.text ?? "无",
            feedback: dialogueFeedbackContext(query: "生活 陪伴 任务 休息", scene: "idle_companion"))
          let result = try await completeAI([
            ["role": "system", "content": prompt],
            ["role": "user", "content": "自然说一句新的搭话。不要重复这些：\(state.messages.suffix(6).map(\.content).joined(separator: "\n"))"],
          ])
          state.aiRequests += 1; state.aiTokens += result.tokens
          let candidate = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
          if !candidate.isEmpty, candidate.count <= 160 { text = candidate }
        } catch { /* Keep the local fallback. */ }
      }

      idleCompanionBusy = false
      guard state.preferences.idleCompanionEnabled ?? true, hasIdleCompanionSpace,
        lastID == state.messages.last?.id, taskID == state.timer?.taskID,
        phase == state.timer?.phase, wasPaused == state.timer?.paused,
        revision == learningRevision else { save(); return }
      state.preferences.lastIdleCompanionAt = Date()
      if let event, let index = state.learning?.entries.firstIndex(where: { $0.id == event.id }) {
        state.learning?.entries[index].followedUpAt = Date()
      }
      bubble = text; recordDesktopLine(text, scene: "idle_companion"); speak(text); save()
    }
  }
}
