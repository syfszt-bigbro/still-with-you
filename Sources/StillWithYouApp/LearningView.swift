import SwiftUI
import StillWithYouCore

struct LearningPanel: View {
  @ObservedObject var model: AppModel
  var body: some View {
    Card {
      Text(UIStrings.text("习惯与长期记忆")).font(.headline)
      Toggle(UIStrings.text("自动学习与适应"), isOn: Binding(get: { model.learningEnabled }, set: model.setLearningEnabled))
      Text(UIStrings.text("本地即时记录明确偏好与常见事件，纠正冲突、保留临时状态期限；有 AI 时每5条新聊天筛选原话。事件日期不明确时不自动安排跟进。关闭后停止提炼并停止使用自动记忆。"))
        .font(.caption).foregroundStyle(.secondary)
      HStack {
        Button(UIStrings.text(model.learningBusy ? "正在学习…" : "立即更新记忆")) { Task { await model.refreshLearning(force: true) } }
          .disabled(!model.learningEnabled || model.learningBusy)
        if let date = model.state.learning?.lastAnalyzedAt { Text(date, style: .date).font(.caption).foregroundStyle(.secondary) }
      }
      if !model.learningStatus.isEmpty { Text(UIStrings.text(model.learningStatus)).font(.caption) }
      Text("近7天任务与运动依据").font(.subheadline.weight(.semibold))
      Text(ProgressEvidence.summary(tasks: model.state.tasks)).font(.caption).textSelection(.enabled)
      Text(UIStrings.text("实际使用习惯")).font(.subheadline.weight(.semibold))
      if model.habitObservations.isEmpty {
        Text(UIStrings.text("至少需要跨 2 天的 3 次实际专注记录。样本不足时，不推测作息。"))
          .font(.caption).foregroundStyle(.secondary)
      } else {
        ForEach(model.habitObservations, id: \.self) { Text($0).font(.caption) }
      }
      Text(UIStrings.text("陪伴方式反馈")).font(.subheadline.weight(.semibold))
      Text(UIStrings.text("可以说：以后回复简短一点、以后回复详细一点、专注时不要闲聊、专注时可以闲聊。新的明确反馈优先，不改变任务到期提醒。"))
        .font(.caption).foregroundStyle(.secondary)
      if model.learningEnabled {
        let adaptation = model.state.learning?.adaptation
        if let short = adaptation?.shortReplies { Text(UIStrings.text(short ? "当前：简短回答" : "当前：详细回答")).font(.caption) }
        if let quiet = adaptation?.quietFocus { Text(UIStrings.text(quiet ? "当前：专注时减少闲聊" : "当前：专注时允许闲聊")).font(.caption) }
      }
      if model.learningEnabled, let impression = model.state.learning?.impression, !impression.isEmpty {
        Text("当前印象 · 基于有效原话").font(.subheadline.weight(.semibold))
        Text(impression).font(.caption).textSelection(.enabled)
      }
      Text("重听偏好 · 待确认").font(.subheadline.weight(.semibold))
      Text("重听仅作为弱信号，点赞、点踩优先。可删除误判；关闭自动学习后不再使用。").font(.caption).foregroundStyle(.secondary)
      ForEach((model.state.dialogueReplays ?? []).reversed()) { replay in
        VStack(alignment: .leading, spacing: 4) {
          Text("重听 \(replay.replayCount ?? 0) 次 · \(replay.text.prefix(120))").font(.caption)
          Text(replay.inference ?? "待确认").font(.caption).foregroundStyle(.secondary)
          Button("删除这条推测") { model.state.dialogueReplays?.removeAll { $0.messageID == replay.messageID }; model.save() }
        }
      }
      Text(UIStrings.text("学到的用户表达")).font(.subheadline.weight(.semibold))
      if model.learnedEntries.isEmpty { Text(UIStrings.text("还没有提炼的记忆。你可以告诉我你的喜好或日常习惯。" )).font(.caption).foregroundStyle(.secondary) }
      ForEach(model.learnedEntries.reversed()) { entry in
        LearnedMemoryEditor(model: model, entry: entry)
      }
      Text(UIStrings.text("可修改、停用或删除；删除后不会从同一条旧消息重新生成。历史原文保留。这是可更正的记忆积累，不是训练模型。"))
        .font(.caption).foregroundStyle(.secondary)
    }
  }
}
private struct LearnedMemoryEditor: View {
  @ObservedObject var model: AppModel
  let entry: LearnedMemory
  @State private var text = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Divider()
      HStack {
        Text(entry.categoryLabel + " · " + (entry.supersededBy != nil ? "已被更正" : !entry.usable() ? "已停用/过期/结束" : "有效")).font(.caption).foregroundStyle(.secondary)
        Text(entry.date, style: .date).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Toggle(UIStrings.text("使用"), isOn: Binding(get: { entry.active }, set: { value in
          var updated = entry; updated.active = value; model.updateLearnedMemory(updated)
        })).toggleStyle(.switch).fixedSize()
        Button(UIStrings.text("删除"), role: .destructive) { model.deleteLearnedMemory(entry) }
      }
      if entry.category == "event" {
        HStack {
          if let date = entry.dueAt { Text("事件日期：" + Day.key(date)).font(.caption) }
          else { Text("时间未明确，可编辑原话补充日期").font(.caption) }
          Text(entry.eventStatus ?? "planned").font(.caption)
          Button("已完成") { model.setMemoryEvent(entry.id, status: "completed") }
          Button("已取消") { model.setMemoryEvent(entry.id, status: "cancelled") }
        }
      }
      TextField(UIStrings.text("记忆"), text: $text, axis: .vertical).textFieldStyle(.roundedBorder)
      HStack {
        Text(UIStrings.text("依据原话")).font(.caption).foregroundStyle(.secondary)
        Text(entry.evidence).font(.caption).textSelection(.enabled)
      }
      Button(UIStrings.text("保存修改")) {
        var updated = entry; updated.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.kind = "用户修订"
        model.updateLearnedMemory(updated)
      }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 400 || text == entry.text)
    }.onAppear { text = entry.text }
      .onChange(of: entry.text) { _, value in text = value }
  }
}
