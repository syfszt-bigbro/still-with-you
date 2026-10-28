import AppKit
import Charts
import SwiftUI
import StillWithYouCore

extension Color {
  static let ink = Color(red: 0.153, green: 0.157, blue: 0.220)
  static let mist = Color(red: 0.906, green: 0.922, blue: 0.937)
  static let lake = Color(red: 0.365, green: 0.490, blue: 0.651)
  static let apricot = Color(red: 0.949, green: 0.698, blue: 0.471)
  static let moss = Color(red: 0.478, green: 0.573, blue: 0.459)
}
struct Card<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 14) { content }.padding(20).frame(
      maxWidth: .infinity, alignment: .leading
    ).background(.white, in: RoundedRectangle(cornerRadius: 18)).overlay(
      RoundedRectangle(cornerRadius: 18).stroke(Color.ink.opacity(0.06)))
  }
}
struct MainView: View {
  @ObservedObject var model: AppModel
  let tabs = [
    ("今天", "sun.max"), ("排计划", "calendar"), ("统计", "chart.bar.xaxis"), ("陪伴", "bubble.left.and.bubble.right"),
    ("记忆", "book.closed"), ("设置", "slider.horizontal.3"),
  ]
  var body: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        Text(model.companionName).font(.system(size: 29, weight: .medium, design: .serif)).padding(.top, 28)
        Text(UIStrings.text("\(model.userName)的桌面伙伴")).font(.caption).foregroundStyle(.secondary).padding(.bottom, 28)
        ForEach(tabs, id: \.0) { label, icon in
          Button {
            model.tab = label
          } label: {
            Label(label == "陪伴" ? model.companionName : UIStrings.text(label), systemImage: icon).font(
              .system(size: 14, weight: model.tab == label ? .semibold : .regular)
            ).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 13).padding(
              .vertical, 12
            ).background(
              model.tab == label ? Color.lake.opacity(0.11) : .clear,
              in: RoundedRectangle(cornerRadius: 10))
          }.buttonStyle(.plain)
        }
        Spacer()
        Text(model.voice("footer", "你的节奏，一起记得。")).font(.caption).foregroundStyle(.secondary)
        Text(UIStrings.text("本机保存 · 0.2")).font(.caption2).foregroundStyle(.tertiary)
      }.padding(22).frame(width: 180).background(Color.white.opacity(0.65))
      VStack(spacing: 0) {
        if !model.storageError.isEmpty { banner(model.storageError, color: .red) }
        if !model.notice.isEmpty {
          HStack {
            Text(UIStrings.text(model.notice)).font(.callout)
            Spacer()
            Button {
              model.notice = ""
            } label: {
              Image(systemName: "xmark")
            }.buttonStyle(.plain)
          }.padding(12).background(Color.lake.opacity(0.1))
        }
        Group {
          switch model.tab {
          case "今天": TodayView(model: model)
          case "排计划": DayPlanView(model: model)
          case "统计": StatsView(model: model)
          case "陪伴": ChatView(model: model)
          case "记忆": MemoryView(model: model)
          default: SettingsView(model: model)
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }.environment(\.locale, Locale(identifier: model.interfaceLanguage.speechCode))
    .environment(\.layoutDirection, model.interfaceLanguage == .ar ? .rightToLeft : .leftToRight)
    .foregroundStyle(Color.ink).background(Color.mist).tint(.lake).frame(
      minWidth: 900, minHeight: 650
    )
    .sheet(
      isPresented: Binding(get: { model.reviewID != nil }, set: { if !$0 { model.reviewID = nil } })
    ) {
      if let id = model.reviewID, let task = model.state.tasks.first(where: { $0.id == id }) {
        if task.isExpired(activeTaskID: model.state.timer?.taskID) {
          ExpiryReasonView(model: model, task: task)
        } else { ReflectionView(model: model, task: task, phase: model.reviewPhase) }
      }
    }
    .sheet(item: Binding(
      get: {
        model.state.onboarding?.completed == true ? model.pendingHistorySpeakerReview : nil
      },
      set: { value in
        if model.state.onboarding?.completed == true { model.pendingHistorySpeakerReview = value }
      }
    )) { review in
      HistorySpeakerReviewView(model: model, review: review)
        .interactiveDismissDisabled()
    }
    .sheet(isPresented: Binding(
      get: { model.state.onboarding?.completed != true },
      set: { _ in }
    )) { OnboardingView(model: model) }
  }
  func banner(_ text: String, color: Color) -> some View {
    Text(text).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(12)
      .background(color.opacity(0.12))
  }
}

struct HistorySpeakerReviewView: View {
  @ObservedObject var model: AppModel
  let review: PendingHistorySpeakerReview
  @State private var selected: String

  init(model: AppModel, review: PendingHistorySpeakerReview) {
    self.model = model
    self.review = review
    _selected = State(initialValue: review.suggestedSpeaker ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("确认历史对话中的对方").font(.title2.weight(.semibold))
      if review.importedCount > 0 || review.duplicateCount > 0 {
        Text("本次新增 \(review.importedCount) 条原文，跳过重复 \(review.duplicateCount) 条。没有自动生成描述或总结。")
          .font(.callout)
      }
      Text(review.detectionNote).font(.caption).foregroundStyle(.secondary)
      if review.candidates.isEmpty {
        Text("记录中没有明确的说话人字段，无法可靠区分双方。原文仍会保存和搜索，但程序不会猜测谁是对方。")
          .padding().background(Color.mist, in: RoundedRectangle(cornerRadius: 10))
        HStack {
          if review.importedCount > 0 && !review.preservesConfirmedAliases {
            Button("取消并撤销本次导入", role: .destructive) {
              model.cancelHistorySpeakerReview()
            }
          }
          Spacer()
          Button("完成") { model.confirmHistorySpeaker(nil) }.buttonStyle(.borderedProminent)
        }
      } else {
        ScrollView {
          Picker("选择谁是对方", selection: $selected) {
            Text("请手动选择").tag("")
            ForEach(review.candidates) { candidate in
              Text("\(candidate.name) · \(candidate.messageCount) 条" + (candidate.name == review.suggestedSpeaker ? " · 建议" : ""))
                .tag(candidate.name)
            }
          }.pickerStyle(.radioGroup)
        }.frame(maxHeight: 280)
        DisclosureGroup("查看各说话人样例") {
          ForEach(review.candidates) { candidate in
            VStack(alignment: .leading, spacing: 4) {
              Text("\(candidate.name) · \(candidate.messageCount) 条").font(.subheadline.weight(.semibold))
              ForEach(Array(candidate.samples.enumerated()), id: \.offset) { _, sample in
                Text("• \(sample)").font(.caption).textSelection(.enabled)
              }
            }.padding(.vertical, 5)
          }
        }
        Text(review.preservesConfirmedAliases
          ? "这次确认只会追加一个历史名称，不会移除你以前确认过的名称。"
          : "确认后，对方的原话才会用于口吻学习和你我映射；以后每次导入都会重新让你确认。")
          .font(.caption).foregroundStyle(.secondary)
        HStack {
          if review.importedCount > 0 && !review.preservesConfirmedAliases {
            Button("取消并撤销本次导入", role: .destructive) {
              model.cancelHistorySpeakerReview()
            }
          }
          Spacer()
          Button("确认“\(selected)”是对方") { model.confirmHistorySpeaker(selected) }
            .buttonStyle(.borderedProminent).disabled(selected.isEmpty)
        }
      }
    }.padding(28).frame(width: 560)
  }
}
struct TodayView: View {
  @ObservedObject var model: AppModel
  @State private var title = ""
  @State private var focus = 45
  @State private var movement = 15
  @State private var exercise = ""
  @State private var editing: PlanTask?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 6) {
            Text(model.voice("today", "把今天，过得从容一点。")).font(.system(size: 26, weight: .medium, design: .serif))
            Text(UIStrings.text("一段专注，一段运动。\(model.companionName)陪你慢慢来。")).foregroundStyle(.secondary)
          }
          Spacer()
          DatePicker(UIStrings.text("日期"), selection: $model.selectedDay, displayedComponents: .date).labelsHidden()
            .frame(width: 120)
        }
        if let timer = model.state.timer, let task = model.activeTask {
          Card {
            HStack {
              Label(UIStrings.text(timer.phase.title), systemImage: timer.phase == .focus ? "book" : "figure.walk")
                .font(.headline)
              Spacer()
              Text(UIStrings.text(timer.awaitingReflection ? "等待你记录" : timer.paused ? "已暂停" : "进行中")).font(.caption)
                .foregroundStyle(.secondary)
            }
            HStack(alignment: .center) {
              VStack(alignment: .leading, spacing: 8) {
                Text(task.title).font(.title3)
                Text(UIStrings.text(timer.phase == .exercise ? task.exercise : "给眼前这件事一点完整的时间。")).foregroundStyle(
                  .secondary)
              }
              Spacer()
              Text(UIStrings.text(model.clock)).font(.system(size: 50, weight: .light, design: .rounded))
                .monospacedDigit()
            }
            ProgressView(value: min(1, timer.elapsed / timer.duration))
            HStack {
              if !timer.awaitingReflection {
                Button(UIStrings.text(timer.paused ? "继续" : "暂停")) { model.togglePause() }
              }
              Button(UIStrings.text(timer.awaitingReflection ? "填写反馈" : "结束并记录")) { model.endCurrent() }
                .buttonStyle(.borderedProminent)
              Button(UIStrings.text("延长 5 分钟")) { model.extendCurrent() }
              Spacer()
              Text(UIStrings.text("休眠自动暂停")).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
        Card {
          Text(UIStrings.text("今天想完成什么？")).font(.headline)
          TextField(UIStrings.text("例如：读完第三章，整理三个观点"), text: $title).textFieldStyle(.roundedBorder).onSubmit {
            add()
          }
          HStack(spacing: 18) {
            Picker(UIStrings.text("专注"), selection: $focus) {
              ForEach([15, 30, 45], id: \.self) { Text(UIStrings.text("\($0) 分钟")).tag($0) }
            }.frame(width: 160)
            Picker(UIStrings.text("活动"), selection: $movement) {
              ForEach(0...15, id: \.self) { Text(UIStrings.text($0 == 0 ? "0 分钟（不安排）" : "\($0) 分钟")).tag($0) }
            }.frame(width: 190)
            Spacer()
            Button(UIStrings.text("保存并启动")) { add(startNow: true) }.buttonStyle(.borderedProminent).disabled(
              title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (movement > 0 && exercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || model.state.timer != nil || Day.key(model.selectedDay) != Day.key())
            Button(UIStrings.text("保存")) { add() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (movement > 0 && exercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
          }
          ActivityInput(model: model, exercise: $exercise).disabled(movement == 0)
        }
        HStack {
          Text(UIStrings.text("\(model.selectedTasks.filter{!$0.cancelled}.count) 项计划")).font(.headline)
          Spacer()
          Button(UIStrings.text("复制前一天")) { model.copyYesterday() }
        }
        if model.selectedTasks.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "leaf").font(.largeTitle).foregroundStyle(Color.lake)
            Text(UIStrings.text("给今天留一个小小的开始。"))
            Text(UIStrings.text("写下第一项计划，选好专注和运动时长。")).font(.callout).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity).padding(35)
        }
        ForEach(model.selectedTasks) { task in taskCard(task) }
      }.padding(30)
    }.sheet(item: $editing) { task in EditTaskView(model: model, task: task) }
  }
  func add(startNow: Bool = false) {
    guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, movement == 0 || !exercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    model.addTask(title: title, focus: focus, movement: movement, exercise: exercise, startNow: startNow)
    title = ""
    exercise = ""
  }
  func taskCard(_ task: PlanTask) -> some View {
    Card {
      HStack {
        Image(
          systemName: task.focus.outcome == .done && (task.exerciseMinutes == 0 || task.movement.outcome == .done)
            ? "checkmark.circle.fill" : "circle"
        ).foregroundStyle(task.focus.outcome == .done ? Color.lake : .secondary)
        VStack(alignment: .leading, spacing: 4) {
          Text(task.title).font(.headline).strikethrough(task.cancelled)
          if task.isExpired(activeTaskID: model.state.timer?.taskID) { Text(UIStrings.text("已过期 · 计入计划总数，尚未完成")).font(.caption).foregroundStyle(.orange) }
          if let start = task.plannedStart {
            Text(UIStrings.text("计划 \(start.formatted(date: .omitted, time: .shortened)) – \(start.addingTimeInterval(Double(task.focusMinutes + task.exerciseMinutes) * 60).formatted(date: .omitted, time: .shortened))"))
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        Spacer()
        Menu {
          Button(UIStrings.text("修改计划")) { editing = task }.disabled(
            task.isExpired() || task.focus.outcome != .pending || model.state.timer?.taskID == task.id)
          Button(UIStrings.text("删除计划"), role: .destructive) { model.deleteTask(task) }.disabled(model.state.timer?.taskID == task.id)
          Button(UIStrings.text("上移")) { model.move(task, by: -1) }
          Button(UIStrings.text("下移")) { model.move(task, by: 1) }
          Button(UIStrings.text(task.cancelled ? "恢复计划" : "取消计划")) { model.cancel(task) }.disabled(
            task.isExpired() || model.state.timer?.taskID == task.id)
        } label: {
          Image(systemName: "ellipsis")
        }.menuStyle(.borderlessButton).frame(width: 22)
      }
      if task.cancelled {
        Text(UIStrings.text("已取消 · 保留记录，不计入完成率")).font(.caption).foregroundStyle(.secondary)
      } else {
        HStack(alignment: .top, spacing: 20) {
          phaseBlock(task, .focus)
          Divider()
          phaseBlock(task, .exercise)
        }
      }
      if let reason = task.expiryReason, !reason.isEmpty {
        Text(reason).font(.caption).foregroundStyle(.secondary)
      }
    }.opacity(task.cancelled ? 0.6 : 1)
  }
  func phaseBlock(_ task: PlanTask, _ phase: Phase) -> some View {
    let r = phase == .focus ? task.focus : task.movement
    return VStack(alignment: .leading, spacing: 10) {
      Label(UIStrings.text(
        "\(phase.title) · \(phase == .focus ? task.focusMinutes:task.exerciseMinutes) 分钟"),
        systemImage: phase == .focus ? "book" : "figure.walk"
      ).font(.callout)
      if phase == .exercise && task.exerciseMinutes > 0 { Text(UIStrings.text(task.exercise)).font(.caption).foregroundStyle(.secondary) }
      if phase == .exercise && task.exerciseMinutes == 0 {
        Text(UIStrings.text("本轮不安排活动")).font(.caption).foregroundStyle(.secondary)
      } else if task.isExpired(activeTaskID: model.state.timer?.taskID) {
        if phase == .focus { Button(UIStrings.text("说明原因")) { model.openReview(task, phase) } }
      } else if r.outcome == .pending {
        HStack {
          Button(UIStrings.text(phase == .focus ? "启动专注" : "启动活动")) { model.start(task, phase: phase) }.disabled(
            task.isExpired(activeTaskID: model.state.timer?.taskID) || model.state.timer != nil || (phase == .exercise && task.focus.outcome == .pending))
          Button(UIStrings.text("补记")) { model.openReview(task, phase) }.disabled(
            model.state.timer?.taskID == task.id && model.state.timer?.phase == phase)
        }
      } else {
        HStack {
          Text(UIStrings.text(r.outcome.title)).foregroundStyle(r.outcome == .done ? Color.lake : .secondary)
          Text(UIStrings.text(r.score.map { "\($0) / 10" } ?? "未评分")).monospacedDigit()
          Spacer()
          Button(UIStrings.text("修改记录")) { model.openReview(task, phase) }
        }.font(.caption)
        ReflectionTimes(record: r)
        if !r.note.isEmpty { Text(r.note).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
struct ActivityInput: View {
  @ObservedObject var model: AppModel
  @Binding var exercise: String
  @State private var managing = false
  @State private var newTag = ""
  private var tags: [String] { model.state.preferences.activityTags ?? ["踱步", "放空", "锻炼", "喝水"] }
  private var trimmedTag: String { newTag.trimmingCharacters(in: .whitespacesAndNewlines) }
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(UIStrings.text("活动内容")).foregroundStyle(.secondary)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack {
            ForEach(tags, id: \.self) { option in
              Button(UIStrings.text(option)) { exercise = option }
                .tint(exercise == option ? Color.lake : Color.secondary)
            }
          }
        }
        Button(UIStrings.text("管理标签"), systemImage: "plus") { managing = true }
      }
      Text(model.voice("activity", "选一项你想做的活动吧。")).font(.caption).foregroundStyle(.secondary)
      TextField(UIStrings.text("请选择上方标签，或自己输入活动内容"), text: $exercise).textFieldStyle(.roundedBorder)
      if exercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        Text(UIStrings.text("请选择或填写活动内容后再保存。")).font(.caption).foregroundStyle(.secondary)
      }
    }.sheet(isPresented: $managing) {
      VStack(alignment: .leading, spacing: 16) {
        Text(UIStrings.text("活动标签")).font(.title2)
        Text(UIStrings.text("所有计划共用这些选项。删除标签不会修改已填写的任务。")).font(.caption).foregroundStyle(.secondary)
        ScrollView {
          VStack {
            ForEach(tags, id: \.self) { option in
              HStack {
                Text(UIStrings.text(option))
                Spacer()
                Button(UIStrings.text("删除"), role: .destructive) {
                  model.state.preferences.activityTags = tags.filter { $0 != option }
                  model.save()
                }.accessibilityLabel("删除标签：" + option)
              }.padding(.vertical, 4)
            }
          }
        }.frame(maxHeight: 220)
        HStack {
          TextField(UIStrings.text("新标签名称"), text: $newTag).textFieldStyle(.roundedBorder)
          Button(UIStrings.text("添加")) {
            model.state.preferences.activityTags = tags + [trimmedTag]
            model.save()
            newTag = ""
          }.disabled(trimmedTag.isEmpty || tags.contains(trimmedTag))
        }
        HStack { Spacer(); Button(UIStrings.text("完成")) { managing = false } }
      }.padding(24).frame(width: 440)
    }
  }
}
struct EditTaskView: View {
  @ObservedObject var model: AppModel
  var task: PlanTask
  @Environment(\.dismiss) var dismiss
  @State var title = ""
  @State var focus = 30
  @State var movement = 10
  @State var exercise = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(UIStrings.text("修改计划")).font(.title2)
      TextField(UIStrings.text("任务"), text: $title)
      Picker(UIStrings.text("专注"), selection: $focus) {
        ForEach([15, 30, 45], id: \.self) { Text(UIStrings.text("\($0) 分钟")).tag($0) }
      }
      Picker(UIStrings.text("活动"), selection: $movement) {
        ForEach(0...15, id: \.self) { Text(UIStrings.text($0 == 0 ? "0 分钟（不安排）" : "\($0) 分钟")).tag($0) }
      }
      ActivityInput(model: model, exercise: $exercise).disabled(movement == 0)
      HStack {
        Button(UIStrings.text("取消")) { dismiss() }
        Spacer()
        Button(UIStrings.text("保存")) {
          if let i = model.state.tasks.firstIndex(where: { $0.id == task.id }), !model.state.tasks[i].isExpired() {
            model.state.tasks[i].title = title
            model.state.tasks[i].focusMinutes = focus
            model.state.tasks[i].exerciseMinutes = movement
            model.state.tasks[i].exercise = exercise
            model.save()
          }
          dismiss()
        }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || (movement > 0 && exercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
      }
    }.padding(30).frame(width: 400).onAppear {
      title = task.title
      focus = task.focusMinutes
      movement = task.exerciseMinutes
      exercise = task.exercise
    }
  }
}
struct ReflectionTimes: View {
  let record: Reflection
  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      if let start = record.startedAt { Text(UIStrings.text("实际开始：\(start.formatted(date: .numeric, time: .standard))")) }
      if let end = record.endedAt { Text(UIStrings.text("实际结束：\(end.formatted(date: .numeric, time: .standard))")) }
      if record.startedAt == nil || record.endedAt == nil, let recorded = record.recordedAt {
        Text(UIStrings.text("记录于：\(recorded.formatted(date: .numeric, time: .standard))"))
        Text(UIStrings.text("未记录完整起止时间，可在修改记录中补充。"))
      }
      Text("实际用时：\(record.seconds / 60, specifier: "%.1f") 分钟（不含暂停）")
    }.font(.caption2).foregroundStyle(.secondary)
  }
}
struct ReflectionView: View {
  @ObservedObject var model: AppModel
  var task: PlanTask
  var phase: Phase
  @State var outcome: Outcome = .done
  @State var note = ""
  @State private var taskTitle = ""
  @State var score = 7
  @State var rated = false
  @State var minutes = 0.0
  @State private var includeTimes = false
  @State private var startedAt = Date()
  @State private var endedAt = Date()
  @State private var loaded = false
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(UIStrings.text("\(phase.title)结束，留一点回声。")).font(.system(size: 23, weight: .medium, design: .serif))
      Text(UIStrings.text(phase == .focus ? "专注任务内容" : "运动类型")).font(.headline)
      TextField(UIStrings.text(phase == .focus ? "任务内容（可补充或修改）" : "例如：散步、吊环、拉伸"), text: $taskTitle, axis: .vertical)
        .textFieldStyle(.roundedBorder).lineLimit(1...3)
      Picker(UIStrings.text("完成情况"), selection: $outcome) {
        ForEach([Outcome.done, .partial, .skipped], id: \.self) { Text(UIStrings.text($0.title)).tag($0) }
      }.pickerStyle(.segmented)
      Text(model.voice("feedback", "实际做了什么？感觉怎么样？")).font(.headline)
      TextEditor(text: $note).font(.body).frame(height: 100).padding(6).overlay(
        RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.2)))
      HStack {
        Text(UIStrings.text("实际用时"))
        TextField(UIStrings.text("分钟"), value: $minutes, format: .number.precision(.fractionLength(1)))
          .textFieldStyle(.roundedBorder).frame(width: 80)
        Text(UIStrings.text("分钟")).foregroundStyle(.secondary)
      }
      Toggle(UIStrings.text("记录实际开始和结束时间"), isOn: $includeTimes)
      if includeTimes {
        HStack { Text(UIStrings.text("实际开始")); RecordDateInput(value: $startedAt).frame(width: 260, height: 28) }
        HStack { Text(UIStrings.text("实际结束")); RecordDateInput(value: $endedAt).frame(width: 260, height: 28) }
        if endedAt < startedAt { Text(UIStrings.text("结束时间不能早于开始时间。")).font(.caption).foregroundStyle(.red) }
      } else {
        Text(UIStrings.text("未启用时仅保留记录时间，不推算实际起止时间。")).font(.caption).foregroundStyle(.secondary)
      }
      Toggle(UIStrings.text("为这次\(phase.title)评分"), isOn: $rated)
      if rated {
        HStack {
          ForEach(0...10, id: \.self) { n in
            Button(UIStrings.text("\(n)")) { score = n }.buttonStyle(.plain).frame(width: 30, height: 32)
              .background(
                score == n ? Color.lake : Color.mist, in: RoundedRectangle(cornerRadius: 6)
              ).foregroundStyle(score == n ? .white : Color.ink)
          }
        }
      }
      HStack {
        Button(UIStrings.text("稍后填写")) { model.reviewID = nil }
        Spacer()
        Button(UIStrings.text("保存记录")) {
          model.record(
            id: task.id, phase: phase, outcome: outcome, note: note, score: rated ? score : nil,
            seconds: minutes * 60, startedAt: includeTimes ? startedAt : nil, endedAt: includeTimes ? endedAt : nil, clearTimes: !includeTimes, title: phase == .focus ? taskTitle : nil, exercise: phase == .exercise ? taskTitle : nil)
        }.buttonStyle(.borderedProminent).disabled(
          taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || taskTitle.count > 500 ||
          note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !minutes.isFinite
            || minutes < 0 || minutes > 1440 || (includeTimes && endedAt < startedAt))
      }
    }.padding(30).frame(width: 465).onAppear {
      guard !loaded else { return }; loaded = true
      taskTitle = phase == .focus ? task.title : task.exercise
      let r = phase == .focus ? task.focus : task.movement
      outcome = r.outcome == .pending ? .done : r.outcome
      note = r.note
      score = r.score ?? 7
      rated = r.score != nil
      let running = model.state.timer.flatMap { $0.taskID == task.id && $0.phase == phase ? $0 : nil }
      let actualStart = running?.startedAt ?? r.startedAt
      let actualEnd = running?.endedAt ?? r.endedAt
      includeTimes = actualStart != nil && actualEnd != nil
      endedAt = actualEnd ?? r.recordedAt ?? Date()
      startedAt = actualStart ?? endedAt.addingTimeInterval(-r.seconds)

      if let t = model.state.timer, t.taskID == task.id, t.phase == phase {
        minutes = (t.elapsed / 6).rounded() / 10
      } else {
        minutes = r.seconds / 60
      }
    }
  }
}
struct ChatView: View {
  @ObservedObject var model: AppModel
  var compact = false
  private var input: String {
    get { model.chatDraft }
    nonmutating set { model.chatDraft = newValue }
  }
  @State private var search = ""
  @FocusState private var inputFocused: Bool
  @State private var scrollToLatestRequest = 0
  var messages: [ChatMessage] {
    model.chatMessages.filter {
      search.isEmpty || $0.content.localizedCaseInsensitiveContains(search)
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(compact ? "\(model.companionName) · 聊一会儿" : model.voice("chat", "\(model.userName)，来坐一会儿。")).font(
            .system(size: compact ? 20 : 26, weight: .medium, design: .serif))
          Text(UIStrings.text(model.connectionStatus)).font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button {
          model.state.preferences.speechEnabled = !(model.state.preferences.speechEnabled ?? true)
          model.stopSpeaking(); model.save()
        } label: {
          Image(systemName: (model.state.preferences.speechEnabled ?? true) ? "speaker.wave.2" : "speaker.slash")
        }.help((model.state.preferences.speechEnabled ?? true) ? "关闭语音播报" : "开启语音播报")
        if !compact { Button(UIStrings.text("导出聊天")) { model.exportChats() } }
      }
      if let task = model.scheduledPromptTask {
        VStack(alignment: .leading, spacing: 8) {
          Text("计划开始确认 · \(task.title)").font(.headline)
          Text(UIStrings.text(model.state.timer == nil ? "现在开始这项专注吗？" : "当前还有计时，请先结束或记录，再开始新任务。"))
            .font(.caption)
          HStack {
            Button(UIStrings.text("现在开始")) { model.respondToScheduledStart("start") }.buttonStyle(.borderedProminent).disabled(model.state.timer != nil)
            Button(UIStrings.text("5 分钟后提醒")) { model.respondToScheduledStart("later") }
          }
          Button(UIStrings.text("今天不再提醒这项")) { model.respondToScheduledStart("dismiss") }.font(.caption)
        }.padding(12).background(Color.lake.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
      }
      if !model.chatStartChoices.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text("选择要启动的专注任务").font(.headline)
          ForEach(model.chatStartChoices) { task in
            Button("\(task.title) · \(task.focusMinutes) 分钟") { model.startFromChat(task.id) }
              .disabled(model.state.timer != nil)
          }
          Button("取消") { model.chatStartIDs = [] }
        }.padding(10).background(Color.lake.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
      }
      if model.state.timer?.awaitingReflection == true {
        HStack {
          Text(UIStrings.text("\(model.phaseTitle)已到期，可以回复我，或直接记录。")).font(.caption)
          Spacer()
          Button(UIStrings.text("填写反馈")) { model.showMain?(); model.endCurrent() }
          Button(UIStrings.text("停止朗读")) { model.stopSpeaking() }
        }
      }
      if !compact { TextField(UIStrings.text("搜索聊天内容"), text: $search).textFieldStyle(.roundedBorder) }
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(messages) { message in
              HStack(alignment: .top) {
                if message.role == "user" { Spacer(minLength: 30) }
                VStack(alignment: .leading, spacing: 6) {
                  Text(UIStrings.text(message.role == "user" ? model.userName : model.companionName)).font(.caption).foregroundStyle(
                    .secondary)
                  if let target = model.feedbackTarget(for: message) {
                    Button { model.openMessageFeedback(message) } label: {
                      Text(message.content).environment(\.layoutDirection, model.voiceLanguage == .ar ? .rightToLeft : .leftToRight)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).help("点击打开这项任务的反馈与评分")
                    Button(UIStrings.text((target.phase == .focus ? target.task.focus : target.task.movement).outcome == .pending ? "填写反馈 / 评分" : "查看或修改反馈 / 评分")) {
                      model.openMessageFeedback(message)
                    }.buttonStyle(.bordered)
                  } else {
                  Text(message.content).environment(\.layoutDirection, model.voiceLanguage == .ar ? .rightToLeft : .leftToRight).textSelection(.enabled).fixedSize(
                    horizontal: false, vertical: true)
                  }
                  Text(UIStrings.text(message.date.formatted(date: .abbreviated, time: .shortened))).font(.caption2)
                    .foregroundStyle(.tertiary)
                }.padding(14).background(
                  message.role == "user" ? Color.lake.opacity(0.12) : Color.white,
                  in: RoundedRectangle(cornerRadius: 14)
                ).modifier(DialogueRating(model: model, message: message)).contextMenu {
                  Button(UIStrings.text("记住这段话")) {
                    model.state.memories.append(SavedMemory(text: message.content))
                    model.save()
                    model.notice = "已加入记忆，可以在记忆页修改或删除。"
                  }
                }
                if message.role != "user" { Spacer(minLength: 30) }
              }.id(message.id)
            }
            if model.busy || model.preparingSpeech {
              Label(UIStrings.text(model.preparingSpeech ? "正在准备语音…" : "\(model.companionName)在想…"), systemImage: "ellipsis.bubble").foregroundStyle(.secondary).font(
                .caption)
            }
            Color.clear.frame(height: 1).id("bottom")
          }.padding(.vertical, 8)
        }.task {
          await Task.yield()
          proxy.scrollTo("bottom", anchor: .bottom)
          try? await Task.sleep(nanoseconds: 80_000_000)
          guard !Task.isCancelled else { return }
          proxy.scrollTo("bottom", anchor: .bottom)
        }.onChange(of: model.chatFocusRequest) { _, _ in
          proxy.scrollTo("bottom", anchor: .bottom)
        }.onChange(of: model.chatMessages.last?.id) { _, _ in
          // Desktop chat and the main window share one message store. Keep the compact
          // window updated and pinned to the newest message on every append or edit.
          Task { @MainActor in
            await Task.yield()
            proxy.scrollTo("bottom", anchor: .bottom)
          }
        }.id(model.chatMessages.count)
        .onChange(of: scrollToLatestRequest) { _, _ in
          Task { @MainActor in
            await Task.yield()
            proxy.scrollTo("bottom", anchor: .bottom)
            try? await Task.sleep(nanoseconds: 80_000_000)
            proxy.scrollTo("bottom", anchor: .bottom)
          }
        }
      }
      if compact && !model.notice.isEmpty {
        Text(UIStrings.text(model.notice)).font(.caption).foregroundStyle(.secondary).lineLimit(3)
      }
      HStack(alignment: .bottom) {
        ChatInput(text: $model.chatDraft, placeholder: UIStrings.text("跟\(model.companionName)说点什么…"), focusRequest: compact ? model.chatFocusRequest : nil, submit: send)
          .frame(height: 48).padding(.horizontal, 12).background(.white, in: RoundedRectangle(cornerRadius: 10))
        Button(action: send) { Image(systemName: "arrow.up").font(.headline).padding(8) }
          .buttonStyle(.borderedProminent)
          .help(UIStrings.text("发送"))
      }
      HStack {
        Text(UIStrings.text("文字自动保存在本机")).font(.caption2).foregroundStyle(.secondary)
        Spacer()
        if !model.apiReady {
          Button(UIStrings.text("连接设置")) {
            model.tab = "设置"
            model.showMain?()
          }.font(.caption)
        }
      }
    }.padding(compact ? 18 : 30).background(Color.mist)
      .environment(\.locale, Locale(identifier: model.interfaceLanguage.speechCode))
      .environment(\.layoutDirection, model.interfaceLanguage == .ar ? .rightToLeft : .leftToRight)
      .onChange(of: model.chatFocusRequest) { _, _ in if compact { inputFocused = true } }
      .onAppear { if compact { inputFocused = true } }
  }
  func send() {
    let text = input
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !model.busy else { return }
    input = ""
    // Show the user's message immediately, without waiting for the AI request to finish.
    scrollToLatestRequest += 1
    Task {
      await model.askAI(text)
      scrollToLatestRequest += 1
    }
  }
}
struct StatsView: View {
  @ObservedObject var model: AppModel
  @State var period = "周"
  @State var anchor = Date()
  var interval: DateInterval {
    var cal = Calendar.current
    cal.firstWeekday = 2
    return cal.dateInterval(
      of: period == "日" ? .day : period == "周" ? .weekOfYear : .month, for: anchor)!
  }
  var tasks: [PlanTask] {
    model.state.tasks.filter {
      guard $0.deletedAt == nil, let d = Day.parse($0.day) else { return false }
      return d >= interval.start && d < interval.end
    }
  }
  var stats: Statistics { Statistics(tasks: tasks) }
  var days: [String] {
    var a: [String] = []
    var d = interval.start
    while d < interval.end {
      a.append(Day.key(d))
      d = Calendar.current.date(byAdding: .day, value: 1, to: d)!
    }
    return a
  }
  var label: String {
    "\(Day.key(interval.start)) 至 \(Day.key(interval.end.addingTimeInterval(-1)))"
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack {
          VStack(alignment: .leading, spacing: 6) {
            Text(model.voice("stats", "每一点努力，都有回声。")).font(.system(size: 26, weight: .medium, design: .serif))
            Text(UIStrings.text(label)).foregroundStyle(.secondary)
          }
          Spacer()
          Picker(UIStrings.text("范围"), selection: $period) {
            ForEach(["日", "周", "月"], id: \.self) { Text(UIStrings.text($0)).tag($0) }
          }.pickerStyle(.segmented).frame(width: 145)
        }
        HStack {
          Button {
            anchor = Calendar.current.date(
              byAdding: period == "日" ? .day : period == "周" ? .weekOfYear : .month, value: -1,
              to: anchor)!
          } label: {
            Image(systemName: "chevron.left")
          }
          DatePicker(UIStrings.text("查看"), selection: $anchor, displayedComponents: .date)
          Button {
            anchor = Calendar.current.date(
              byAdding: period == "日" ? .day : period == "周" ? .weekOfYear : .month, value: 1,
              to: anchor)!
          } label: {
            Image(systemName: "chevron.right")
          }
          Spacer()
          Button(UIStrings.text("回到今天")) { anchor = Date() }
        }
        HStack(spacing: 14) {
          metric("任务完成", value: "\(stats.focusDone) / \(stats.planned)", foot: rate(.focus))
          metric("运动完成", value: "\(stats.exerciseDone) / \(stats.exercisePlanned)", foot: rate(.exercise))
          metric("过期计划", value: "\(stats.expired(activeTaskID: model.state.timer?.taskID))", foot: "计入完成率分母；未评分不按零分")
          metric("完整轮次", value: "\(stats.completeRounds)", foot: "本轮所有已安排环节完成")
        }
        Card {
          Text(UIStrings.text("每天的完成情况")).font(.headline)
          Chart {
            ForEach(days, id: \.self) { day in
              let s = Statistics(tasks: tasks.filter { $0.day == day })
              BarMark(x: .value("日期", String(day.suffix(5))), y: .value("次数", s.focusDone))
                .foregroundStyle(by: .value("类型", "专注")).position(by: .value("类型", "专注"))
              BarMark(x: .value("日期", String(day.suffix(5))), y: .value("次数", s.exerciseDone))
                .foregroundStyle(by: .value("类型", "运动")).position(by: .value("类型", "运动"))
            }
          }.chartForegroundStyleScale([
            "专注": Color.lake, "运动": Color(red: 0.49, green: 0.66, blue: 0.61),
          ]).chartYScale(
            domain:
              0...max(
                1, days.map { d in tasks.filter { $0.day == d && !$0.cancelled }.count }.max() ?? 1)
          ).frame(height: 200)
          Text(UIStrings.text("无计划的日期不计为失败；部分完成单独保留。")).font(.caption).foregroundStyle(.secondary)
        }
        HStack(spacing: 14) {
          metric(
            "专注自评", value: average(.focus),
            foot: "\(stats.scores(.focus).count) 次评分 · \(Int(stats.minutes(.focus))) 分钟")
          metric(
            "运动自评", value: average(.exercise),
            foot: "\(stats.scores(.exercise).count) 次评分 · \(Int(stats.minutes(.exercise))) 分钟")
        }
        Card {
          HStack {
            Text(UIStrings.text("和\(model.companionName)一起复盘")).font(.headline)
            Spacer()
            Button(UIStrings.text(model.busy ? "正在想…" : "生成本期分析")) {
              Task { await model.analyze(tasks: tasks, label: label) }
            }.buttonStyle(.borderedProminent).disabled(model.busy)
          }
          Text("根据真实记录复盘；基础模式生成本地统计，连接 AI 后可生成智能分析。评分不会被修改。").font(.caption).foregroundStyle(.secondary)
          if let report = model.state.reports.last(where: { $0.period == label }) {
            Text(report.content).textSelection(.enabled)
            Text(UIStrings.text("生成于 \(report.date.formatted())")).font(.caption2).foregroundStyle(.secondary)
          }
        }
        if !tasks.isEmpty {
          Card {
            Text(UIStrings.text("本期记录")).font(.headline)
            ForEach(tasks) { t in
              VStack(alignment: .leading, spacing: 4) {
                Text("\(t.day) · \(t.title)").font(.callout.weight(.medium))
                Text(UIStrings.text(
                  t.cancelled
                    ? "已取消" : "任务：\(t.focus.outcome.title) · 活动：\(t.exerciseMinutes == 0 ? "未安排" : t.movement.outcome.title)"
                )).font(.caption).foregroundStyle(.secondary)
                if let reason = t.expiryReason, !reason.isEmpty { Text(reason).font(.caption) }
                if !t.focus.note.isEmpty { Text(UIStrings.text(t.focus.note)).font(.caption) }
                if !t.movement.note.isEmpty { Text(UIStrings.text("运动：" + t.movement.note)).font(.caption) }
                if t.focus.outcome != .pending { Text(UIStrings.text("专注时间")).font(.caption); ReflectionTimes(record: t.focus) }
                if t.exerciseMinutes > 0 && t.movement.outcome != .pending { Text(UIStrings.text("活动时间")).font(.caption); ReflectionTimes(record: t.movement) }
              }
            }
          }
        }
      }.padding(30)
    }
  }
  func rate(_ p: Phase) -> String { stats.rate(p).map { "完成率 \(Int($0*100))%" } ?? "本期无计划" }
  func average(_ p: Phase) -> String {
    stats.average(p).map { String(format: "%.1f / 10", $0) } ?? "未评分"
  }
  func metric(_ title: String, value: String, foot: String) -> some View {
    Card {
      Text(UIStrings.text(title)).font(.caption).foregroundStyle(.secondary)
      Text(UIStrings.text(value)).font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
      Text(UIStrings.text(foot)).font(.caption).foregroundStyle(.secondary)
    }
  }
}
struct MemoryView: View {
  @ObservedObject var model: AppModel
  @State var query = ""
  @State var newMemory = ""
  @State private var correction = ""
  @State private var correctionTarget = CorrectionTarget.persona
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        Text(model.voice("memory", "记得你，也听你更正。")).font(.system(size: 26, weight: .medium, design: .serif))
        LearningPanel(model: model)
        Card {
          Text("人物与关系记忆 · 可纠正、可回滚").font(.headline)
          Text("运行顺序固定为：人物规则决定怎么回应 → 只检索本轮相关且有原文证据的往事 → 用人物的方式输出。")
            .font(.caption).foregroundStyle(.secondary)
          Picker("纠正对象", selection: $correctionTarget) {
            Text("人物与说话方式").tag(CorrectionTarget.persona)
            Text("往事与事实").tag(CorrectionTarget.memory)
          }.pickerStyle(.segmented)
          TextField("例如：她不会在普通聊天里主动说永远陪着我", text: $correction, axis: .vertical)
            .textFieldStyle(.roundedBorder)
          Button("保存纠正并创建版本") {
            model.applyKnowledgeCorrection(correction, target: correctionTarget)
            correction = ""
          }.disabled(correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          if !model.effectiveKnowledge.corrections.isEmpty {
            Text("当前生效的纠正").font(.subheadline.weight(.semibold))
            ForEach(model.effectiveKnowledge.corrections.filter(\.active).suffix(8)) { item in
              Text("• \(item.statement)").font(.caption)
            }
          }
          DisclosureGroup("关系记忆总结（\(model.effectiveKnowledge.memories.count)）· 可替换、可删除") {
            Text("总结是可选卡片，与历史原文分开保存。修改或删除总结不会删除导入的聊天。")
              .font(.caption).foregroundStyle(.secondary)
            ForEach(model.effectiveKnowledge.memories.suffix(50)) { memory in
              RelationshipMemoryEditor(model: model, memory: memory)
            }
          }
          if let versions = model.state.knowledgeVersions, !versions.isEmpty {
            DisclosureGroup("版本历史（\(versions.count)）") {
              ForEach(versions.reversed()) { version in
                HStack {
                  VStack(alignment: .leading) {
                    Text(version.reason).font(.caption)
                    Text(version.createdAt.formatted()).font(.caption2).foregroundStyle(.secondary)
                  }
                  Spacer()
                  Button("恢复") { model.rollbackKnowledge(to: version.id) }
                }
              }
            }
          }
        }
        Card {
          HStack {
            Text(UIStrings.text("历史对话")).font(.headline)
            Spacer()
            Text(UIStrings.text("\(model.library.history.count) 条")).foregroundStyle(.secondary)
          }
          Toggle(UIStrings.text("聊天时参考导入的历史记忆"), isOn: $model.state.historyEnabled).onChange(
            of: model.state.historyEnabled
          ) { _, _ in
            model.updateVoiceSignature(); model.save()
            Task { await model.refreshVoice() }
          }
          Text(UIStrings.text("梦、玩笑和现实记录分别处理；只发送与本轮聊天相关的片段。关闭后，旧聊天不再参与 AI 回复和人物用语生成。")).font(.caption).foregroundStyle(
            .secondary)
          HStack {
            Button(UIStrings.text("导入历史聊天…")) { model.importHistory() }
              .disabled(model.historySpeakerDetectionBusy)
            Button(model.historySpeakerDetectionBusy ? "正在识别说话人…" : "重新识别并添加对方名称") {
              model.reviewImportedHistorySpeakers()
            }.disabled(model.historySpeakerDetectionBusy || model.library.history.isEmpty)
            Text(UIStrings.text("可多选；支持 UTF-8 TXT / Markdown / JSON / JSONL 与 WeFlow Markdown，每个文件最多 10 MB。"))
              .font(.caption).foregroundStyle(.secondary)
          }
          Text("导入只保存原文，不强制生成总结。记录含明确说话人时，启用 AI 会发送少量名称与样例用于建议；无论建议是什么，最终都由你选择谁是对方。")
            .font(.caption).foregroundStyle(.secondary)
          if !model.confirmedHistorySpeakers.isEmpty {
            Text("已确认属于对方的历史名称：\(model.confirmedHistorySpeakers.joined(separator: "、"))")
              .font(.caption.weight(.semibold))
          }
          Text(UIStrings.text("JSON 可用消息数组，每条含 role/content 或 speaker/text；文本按原文分段，保留原有称呼，不计入任务统计。"))
            .font(.caption).foregroundStyle(.secondary)
          TextField(UIStrings.text("搜索历史内容或日期，例如：梦、用户、2026-04"), text: $query).textFieldStyle(.roundedBorder)
          ForEach(model.library.search(query), id: \.id) { m in
            VStack(alignment: .leading, spacing: 4) {
              Text("\(m.timestamp) · \(m.speaker)").font(.caption).foregroundStyle(
                .secondary)
              Text(m.text).font(.callout).textSelection(.enabled)
            }.padding(.vertical, 4)
          }
        }
        Card {
          Text(UIStrings.text("希望\(model.companionName)记住的事")).font(.headline)
          TextField(UIStrings.text("例如：工作时请简短提醒，不要打断我"), text: $newMemory, axis: .vertical).textFieldStyle(
            .roundedBorder)
          Button(UIStrings.text("保存记忆")) {
            model.state.memories.append(SavedMemory(text: newMemory))
            newMemory = ""
            model.save()
          }.disabled(newMemory.trimmingCharacters(in: .whitespaces).isEmpty)
          ForEach($model.state.memories) { $memory in
            HStack {
              TextField(UIStrings.text("记忆"), text: $memory.text, axis: .vertical).textFieldStyle(.roundedBorder)
                .onSubmit { model.save() }
              Button {
                model.state.memories.removeAll { $0.id == memory.id }
                model.save()
              } label: {
                Image(systemName: "trash")
              }.help("删除这条手动记忆")
            }
          }
          Text(UIStrings.text("修改后按回车保存。聊天里右键也可以记住一段话。删除手动记忆不删除原聊天。")).font(.caption).foregroundStyle(.secondary)
        }
      }.padding(30)
    }
  }
}

private struct RelationshipMemoryEditor: View {
  @ObservedObject var model: AppModel
  let memory: RelationshipMemory
  @State private var title: String
  @State private var summary: String

  init(model: AppModel, memory: RelationshipMemory) {
    self.model = model
    self.memory = memory
    _title = State(initialValue: memory.title)
    _summary = State(initialValue: memory.summary)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Divider()
      TextField("总结标题", text: $title).textFieldStyle(.roundedBorder)
      TextField("可替换的总结", text: $summary, axis: .vertical)
        .lineLimit(2...6).textFieldStyle(.roundedBorder)
      DisclosureGroup("查看原文证据（\(memory.evidence.count) 条）") {
        ForEach(Array(memory.evidence.enumerated()), id: \.offset) { _, evidence in
          Text("• \(evidence.quote)").font(.caption).textSelection(.enabled)
        }
      }.font(.caption)
      HStack {
        Button("保存替换") {
          model.replaceRelationshipMemory(memory.id, title: title, summary: summary)
        }.disabled(
          title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (title == memory.title && summary == memory.summary))
        Button("删除总结", role: .destructive) { model.deleteRelationshipMemory(memory.id) }
        Spacer()
        Text("原文独立保留").font(.caption2).foregroundStyle(.secondary)
      }
    }.onChange(of: memory.title) { _, value in title = value }
      .onChange(of: memory.summary) { _, value in summary = value }
  }
}
struct SettingsView: View {
  @ObservedObject var model: AppModel
  @State private var apiKey = ""
  @State private var profile = CompanionProfile()
  @State private var showPromptPreview = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        Text(model.voice("settings", "让陪伴，按你的习惯来。")).font(.system(size: 26, weight: .medium, design: .serif))
        Card {
          HStack { Text("安装后配置 · 共 4 步").font(.headline); Spacer(); Button("重新打开配置向导") {
            if model.state.onboarding == nil { model.state.onboarding = OnboardingState() }
            model.state.onboarding?.currentStep = 1; model.state.onboarding?.completed = false; model.save()
          } }
          setupRow(done: model.state.onboarding?.identityCompleted == true, title: "1. 名字与边界", note: "必选")
          setupRow(done: model.hasCustomCharacter, title: "2. 照片与动作包", note: "可选")
          setupRow(done: model.state.onboarding?.memoryConfigured == true, title: "3. 聊天与记忆", note: "可选")
          setupRow(done: model.state.onboarding?.apiConfigured == true, title: "4. AI 与语音", note: "均可选；系统朗读无需 Key")
          Text("未完成可选步骤不会影响计划、计时、桌面互动和本机备份。")
            .font(.caption).foregroundStyle(.secondary)
        }
        Card {
          Text(UIStrings.text("名字与人物设定")).font(.headline)
          LabeledContent("对方的名字") {
            TextField(UIStrings.text("例如：陪伴者"), text: $profile.name).textFieldStyle(.roundedBorder)
          }
          LabeledContent("对方怎么称呼我") {
            TextField(UIStrings.text("例如：用户"), text: $profile.userName).textFieldStyle(.roundedBorder)
          }
          Text(UIStrings.text("一句话描述，也可以写得详细些")).font(.subheadline)
          TextField("例如：她说话简短、有主见，关心生活小事，不会无条件附和。", text: $profile.description, axis: .vertical)
            .lineLimit(3...8).textFieldStyle(.roundedBorder)
          Text(UIStrings.text("人物描述会用于 AI 聊天和复盘。名字与称呼最多 40 字，描述最多 4000 字；历史聊天可选导入。")).font(.caption).foregroundStyle(.secondary)
          HStack {
            Button(UIStrings.text("保存人物设置")) { model.saveProfile(profile); profile = model.profile }.buttonStyle(.borderedProminent)
            Button(UIStrings.text("导入历史聊天…")) { model.importHistory() }
              .disabled(model.historySpeakerDetectionBusy)
          }
        }

        Card {
          DisclosureGroup(isExpanded: $showPromptPreview) {
            ScrollView {
              Text(model.idleCompanionPromptPreview)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .frame(maxHeight: 360)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
          } label: {
            VStack(alignment: .leading, spacing: 5) {
              Text(UIStrings.text("当前生效的主动陪伴提示词")).font(.headline)
              Text("查看 AI 实际收到的人物设定与动态上下文。时间使用设备本地时区，任务、相关记忆和反馈在每次请求时替换。")
                .font(.caption).foregroundStyle(.secondary)
            }
          }
        }

        Card {
          Text(UIStrings.text("人物用语")).font(.headline)
          Text("当前表达风格：" + DialogueStyle.title).font(.subheadline)
          Text("日常聊天独立接话，不默认带入任务统计或催计划；旧 AI 回复只作上下文资料。任务问答仍使用真实记录。").font(.caption).foregroundStyle(.secondary)
          Text("仅调整说话口吻；姓名、称呼、作息、地点、声音、历史记忆及功能保持原设置。").font(.caption).foregroundStyle(.secondary)
          DisclosureGroup("查看完整说话风格规则") {
            Text(DialogueStyle.instruction).font(.caption).textSelection(.enabled)
          }
          Picker(UIStrings.text("操作界面语言"), selection: Binding(get: { model.interfaceLanguage.rawValue }, set: { model.changeInterfaceLanguage($0) })) {
            ForEach(VoiceLanguage.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
          }

          Picker(UIStrings.text("人物语言"), selection: Binding(get: { model.voiceLanguage.rawValue }, set: { model.changeVoiceLanguage($0) })) {
            ForEach(VoiceLanguage.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
          }
          Text("人物语言用于对话、彩蛋和系统朗读；界面语言用于按钮和设置，两者独立保存。可用声音取决于这台 Mac 已安装的系统声音。").font(.caption).foregroundStyle(.secondary)
          Text("已确认属于对方的历史名称：" + (model.confirmedHistorySpeakers.isEmpty
            ? "尚未确认" : model.confirmedHistorySpeakers.joined(separator: "、")))
            .font(.subheadline)
          Text("每次导入后都会先给出识别建议，再由你确认。不同文件里的“她”“assistant”或昵称会分别保存，不会覆盖以前的确认。")
            .font(.caption).foregroundStyle(.secondary)
          Text(UIStrings.text("当前学习对象：\(model.styleSpeaker ?? "尚未识别，请选择对方的历史名字")")).font(.caption).foregroundStyle(.secondary)
          Text(UIStrings.text("各栏引导语和提醒按性格生成；有历史时，优先借用对方在相近场景中的常用语。保存、删除等操作名称保持明确。用语在本机缓存，切换页面不会重复请求。"))
            .font(.caption).foregroundStyle(.secondary)
          Text(UIStrings.text("人物用语会参考历史表达；日常聊天的习惯与长期记忆在“记忆”页管理。不会训练模型或自动修改人物核心性格。")).font(.caption).foregroundStyle(.secondary)
          Button(UIStrings.text(model.voiceBusy ? "正在学习用语…" : "重新学习人物用语")) { Task { await model.refreshVoice(force: true) } }
            .disabled(model.voiceBusy || !model.apiReady)
          if !model.voiceStatus.isEmpty { Text(UIStrings.text(model.voiceStatus)).font(.caption).foregroundStyle(.secondary) }
          Text("需要开启 AI；会发送人物描述及按场景筛选的对方原话，并按所选服务商的 API 用量计费。修改人物或导入历史后会自动更新。").font(.caption).foregroundStyle(.secondary)
        }

        Card {
          Text("桌面照片角色").font(.headline)
          Picker("桌面人物模型", selection: Binding(
            get: { model.state.preferences.desktopCharacterID ?? "default" },
            set: { model.state.preferences.desktopCharacterID = $0; model.save(); model.refreshPet?() }
          )) {
            Text("内置抽象形象").tag("default")
            if model.hasCustomCharacter { Text("我的照片动画卡").tag("custom") }
          }
          Button(model.hasCustomCharacter ? "换一张照片并重新生成…" : "用照片生成动画卡…") { model.importCharacterPhoto() }
          Text("图片只在本机处理。会保留整张照片，生成头像和 11 组带动作标识的轻动画卡；不会用 AI 改人物姿势，原照片也不会被复制进资料库。")
            .font(.caption).foregroundStyle(.secondary)
          ReadingBookSettings(model: model)
          Toggle(UIStrings.text("始终置顶"), isOn: $model.state.preferences.alwaysOnTop).onChange(
            of: model.state.preferences.alwaysOnTop
          ) { _, _ in
            model.save()
            model.refreshPet?()
          }
          HStack {
            Text(UIStrings.text("人物大小"))
            Slider(value: $model.state.preferences.petHeight, in: 180...500, step: 10)
            Text(UIStrings.text("\(Int(model.state.preferences.petHeight))")).monospacedDigit()
          }.onChange(of: model.state.preferences.petHeight) { _, _ in
            model.save()
            model.refreshPet?()
          }
          Toggle(UIStrings.text("加入新任务后朗读回应"), isOn: Binding(
            get: { model.state.preferences.spokenTaskReplies ?? true },
            set: { model.state.preferences.spokenTaskReplies = $0; if !$0 { model.stopSpeaking() }; model.save() }
          ))
          Text(UIStrings.text("加入计划后，会回应任务内容和时长，显示在桌面气泡与页面顶部，并保存到聊天记录。"))
            .font(.caption).foregroundStyle(.secondary)
          Toggle("主动鼓励与陪伴", isOn: Binding(get: { model.state.preferences.idleCompanionEnabled ?? true }, set: { model.state.preferences.idleCompanionEnabled = $0; model.save() }))
          Text("无论有没有任务，安静约10分钟后会偶尔主动搭话；参考实际任务、运动反馈和有效记忆，不打断输入或已有语音，夜间23点至8点不主动插播。").font(.caption).foregroundStyle(.secondary)
          Toggle("任务结束前轻声提醒", isOn: Binding(get: { model.state.preferences.advanceRemindersEnabled ?? true }, set: { model.state.preferences.advanceRemindersEnabled = $0; model.save() }))
          Text("20分钟以上任务剩余8、3分钟时提醒；6–19分钟任务剩余3分钟提醒；3–5分钟任务剩余1分钟提醒。暂停不提醒，每轮各提醒一次。").font(.caption).foregroundStyle(.secondary)
          Toggle(UIStrings.text("到期提示音"), isOn: $model.state.preferences.sound).onChange(
            of: model.state.preferences.sound
          ) { _, _ in model.save() }
          Toggle(UIStrings.text("到期语音朗读"), isOn: Binding(
            get: { model.state.preferences.spokenReminders ?? true },
            set: { model.state.preferences.spokenReminders = $0; if !$0 { model.stopSpeaking() }; model.save() }
          ))
          Text("专注或运动到期时，会打开对话窗口询问完成情况，并按需使用 macOS 系统朗读。文字提醒始终离线可用。")
            .font(.caption).foregroundStyle(.secondary)
          HStack {
            Button(UIStrings.text("开启系统通知")) { model.requestNotifications() }
            Button(UIStrings.text("测试提醒")) {
              model.testReminder()
            }
          }
          Text(UIStrings.text("关闭主窗口仍会计时；退出程序会暂停。电脑休眠后，回来手动继续。")).font(.caption).foregroundStyle(.secondary)
        }
        ClonedSpeechSettings(model: model, voice: model.clonedSpeech)
        Card {
          Text("AI 对话与复盘（可选）").font(.headline)
          Text("不配置 API 也能使用计划、计时、桌面互动、导入、记忆和备份；只有 AI 对话与智能分析需要此步骤。")
            .font(.caption).foregroundStyle(.secondary)
          Picker("服务商", selection: Binding(
            get: { model.state.preferences.resolvedAIProvider.rawValue },
            set: { value in
              model.state.preferences.aiProvider = value
              if value == AIProviderPreset.deepseek.rawValue {
                model.state.preferences.model = "deepseek-chat"
              } else if value == AIProviderPreset.openai.rawValue {
                model.state.preferences.model = "gpt-4.1-mini"
              }
              model.validatedModel = nil; model.save()
            }
          )) {
            ForEach(AIProviderPreset.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
          }
          if model.state.preferences.resolvedAIProvider == .openAICompatible {
            TextField("完整的 chat/completions 地址", text: Binding(
              get: { model.state.preferences.aiEndpoint ?? "" },
              set: { model.state.preferences.aiEndpoint = $0; model.validatedModel = nil; model.save() }
            )).textFieldStyle(.roundedBorder)
          }
          Text(UIStrings.text(model.apiSettingsStatus)).font(.callout)
            .foregroundStyle(model.apiReady && model.aiConnectionIssue.isEmpty ? Color.lake : Color.orange)
            .textSelection(.enabled)
          SecureField(UIStrings.text(
            "API Key（留空保留已保存的密钥）"), text: $apiKey
          ).textFieldStyle(.roundedBorder)
          HStack {
            Button(UIStrings.text("保存密钥")) {
              do {
                try Secrets.set("chat-api", apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                apiKey = ""
                model.aiConnectionIssue = ""
                model.notice = "密钥已保存在 macOS 钥匙串。"
                model.validatedModel = nil
                Task { await model.testAPI() }
              } catch { model.notice = error.localizedDescription }
            }.disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(UIStrings.text("授权读取密钥")) {
              if Secrets.get("chat-api", allowPrompt: true).isEmpty {
                model.notice = "未取得密钥。可以稍后重试授权，或重新填写 API Key；后台不会反复弹窗。"
              } else {
                model.aiConnectionIssue = ""
                model.notice = "密钥已就绪，本次运行无需重复授权。"
                Task { await model.testAPI() }
              }
            }
            Button(UIStrings.text("测试连接")) { Task { await model.testAPI() } }.disabled(model.busy)
            Button(UIStrings.text("清除密钥"), role: .destructive) {
              do {
                try Secrets.set("chat-api", "")
                model.state.preferences.aiEnabled = false
                model.validatedModel = nil
                model.aiConnectionIssue = ""
                model.save()
                model.notice = "密钥已清除。"
              } catch { model.notice = error.localizedDescription }
            }
          }
          Text(UIStrings.text("后台不会弹钥匙串授权框。需要授权时，请主动点击“授权读取密钥”。密钥由固定的独立组件保存在 macOS 钥匙串，普通更新和重启会自动读取。旧版密钥首次迁移可能需要授权一次。")).font(.caption).foregroundStyle(.secondary)
          TextField(UIStrings.text("模型名称"), text: $model.state.preferences.model).textFieldStyle(.roundedBorder)
            .onSubmit { model.save() }
          Toggle("开启 AI，允许发送本轮必要资料", isOn: $model.state.preferences.aiEnabled).onChange(
            of: model.state.preferences.aiEnabled
          ) { _, enabled in
            model.save()
            if enabled { Task { await model.refreshVoice() } }
          }
          Text("会发送最近最多 24 条对话、与本轮相关且有原文证据的记忆，以及必要的当前任务资料；不会上传整个资料库。费用由你选择的 API 服务商收取，测试连接也可能产生极少量费用。")
            .font(.caption)
            .foregroundStyle(.secondary)
          Toggle(UIStrings.text("每天首次打开时，自动生成一句问候"), isOn: $model.state.preferences.autoGreeting).onChange(
            of: model.state.preferences.autoGreeting
          ) { _, _ in model.save() }
          Text(UIStrings.text("累计成功请求 \(model.state.aiRequests) 次 · \(model.state.aiTokens) tokens")).font(.caption)
            .foregroundStyle(.secondary)
        }
        Card {
          Text(UIStrings.text("数据与备份")).font(.headline)
          Button(UIStrings.text("恢复最近删除的计划")) { model.restoreDeletedTask() }.disabled(!model.state.tasks.contains { $0.deletedAt != nil })
          Text(UIStrings.text("记录保存在这台 Mac。备份包含计划、聊天、导入历史和人物设置，不包含 API 密钥。")).font(.caption).foregroundStyle(.secondary)
          HStack {
            Button(UIStrings.text("导出聊天 Markdown")) { model.exportChats() }
            Button(UIStrings.text("导出备份")) { model.exportBackup() }
            Button(UIStrings.text("恢复备份")) { model.restoreBackup() }
            Button(UIStrings.text("打开数据目录")) { NSWorkspace.shared.open(model.directory) }
          }
          Text(UIStrings.text(model.directory.path)).font(.caption2).textSelection(.enabled).foregroundStyle(
            .secondary)
        }
      }.padding(30)
    }.onAppear { profile = model.profile }
  }
  private func setupRow(done: Bool, title: String, note: String) -> some View {
    HStack {
      Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? Color.moss : .secondary)
      Text(title); Spacer(); Text(note).font(.caption).foregroundStyle(.secondary)
    }
  }
}

struct PetHUD: View {
  @ObservedObject var model: AppModel
  private var timerAccent: Color? {
    guard let timer = model.state.timer else { return nil }
    let progress = min(1, max(0, timer.elapsed / max(1, timer.duration)))
    if progress < 1.0 / 3.0 { return Color(red: 0.20, green: 0.62, blue: 0.36) }
    if progress < 2.0 / 3.0 { return Color(red: 0.88, green: 0.64, blue: 0.12) }
    return Color(red: 0.82, green: 0.25, blue: 0.22)
  }
  private var desktopSpeech: some View {
      Button { model.showChat?() } label: {
      Text(model.desktopBubble).environment(\.layoutDirection, model.voiceLanguage == .ar ? .rightToLeft : .leftToRight).font(
        .system(size: 12)
      ).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading).padding(10).background {
        if let timerAccent {
          RoundedRectangle(cornerRadius: 12).fill(timerAccent.opacity(0.22))
        } else {
          RoundedRectangle(cornerRadius: 12).fill(.regularMaterial)
        }
      }
          .contentShape(Rectangle())
      }.buttonStyle(.plain)
        .help("点击和\(model.companionName)聊天")
        .accessibilityLabel("打开与\(model.companionName)的对话：" + model.desktopBubble)
  }
  var body: some View {
    VStack(spacing: 8) {
      Group {
        if let message = model.desktopDialogueMessage {
          desktopSpeech.modifier(DialogueRating(model: model, message: message))
        } else { desktopSpeech }
      }
      HStack(spacing: 9) {
        if let timer = model.state.timer {
          TimerProgressControl(timer: timer, tint: timerAccent ?? Color.lake)
        } else {
          Circle().fill(Color.lake).frame(width: 6, height: 6)
        }
        Text(UIStrings.text(model.state.timer == nil ? "\(model.companionName) · 聊一会儿" : "\(model.phaseTitle) \(model.clock)")).font(
          .system(size: 12, weight: .medium)
        ).monospacedDigit().fixedSize()
        if let timer = model.state.timer, !timer.awaitingReflection {
          Button { model.togglePause() } label: {
            Image(systemName: timer.paused ? "play.fill" : "pause.fill")
          }.help(timer.paused ? "继续计时" : "暂停计时")
            .accessibilityLabel(timer.paused ? "继续计时" : "暂停计时")
        }
        Button {
          model.showChat?()
        } label: {
          Image(systemName: "bubble.left")
        }.help("和\(model.companionName)聊天")
        Button {
          model.tab = "今天"
          model.showMain?()
          if model.state.timer?.awaitingReflection == true { model.endCurrent() }
        } label: {
          Image(systemName: "list.bullet")
        }.help("计划与反馈")
      }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 9).background {
        if let timerAccent {
          Capsule().fill(timerAccent.opacity(0.18))
        } else {
          Capsule().fill(.regularMaterial)
        }
      }
    }.foregroundStyle(Color.ink).padding(5).frame(width: 270, height: 159)
  }
}


/// A display preference only: switching styles never changes the underlying timer.
struct TimerProgressControl: View {
  let timer: FocusTimer
  let tint: Color
  @AppStorage("desktopTimerVisualization") private var style = "hourglass"
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var progress: Double { min(1, max(0, timer.elapsed / max(1, timer.duration))) }
  private var running: Bool { !timer.paused && !timer.awaitingReflection && progress < 1 }
  private var percentage: String {
    String(format: "已完成 %.1f%% · 剩余 %.1f%%", progress * 100, (1 - progress) * 100)
  }
  var body: some View {
    Button { style = style == "hourglass" ? "circle" : "hourglass" } label: {
      TimelineView(.animation(minimumInterval: 0.12, paused: !running || reduceMotion || style == "circle")) { context in
        TimerProgressGlyph(progress: progress, hourglass: style == "hourglass",
          flowing: running && !reduceMotion,
          phase: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.7) / 0.7,
          paused: timer.paused && !timer.awaitingReflection, tint: tint)
          .frame(width: 24, height: 28)
      }.frame(width: 28, height: 30).contentShape(Rectangle())
    }.buttonStyle(.plain)
      .help(percentage + "\n点击切换" + (style == "hourglass" ? "圆形" : "沙漏"))
      .accessibilityLabel(style == "hourglass" ? "沙漏进度，点击切换圆形" : "圆形进度，点击切换沙漏")
      .accessibilityValue(percentage)
  }
}

struct TimerProgressGlyph: View {
  let progress: Double
  let hourglass: Bool
  let flowing: Bool
  let phase: Double
  let paused: Bool
  let tint: Color
  var body: some View {
    Canvas { context, size in
      let ink = Color.ink
      let sand = tint
      let p = min(1, max(0, progress))
      if !hourglass {
        let radius = min(size.width, size.height) / 2 - 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let circle = Path(ellipseIn: rect)
        context.fill(circle, with: .color(sand.opacity(0.12)))
        if p >= 1 { context.fill(circle, with: .color(sand)) }
        else if p > 0 {
          var wedge = Path()
          wedge.move(to: center)
          wedge.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + p * 360), clockwise: false)
          wedge.closeSubpath()
          context.fill(wedge, with: .color(sand))
        }
        context.stroke(circle, with: .color(ink.opacity(0.8)), lineWidth: 1.3)
      } else {
        let left = 3.0, right = size.width - 3, middle = size.width / 2
        let top = 3.0, neck = size.height / 2, bottom = size.height - 3
        var upper = Path()
        upper.move(to: CGPoint(x: left, y: top)); upper.addLine(to: CGPoint(x: right, y: top))
        upper.addLine(to: CGPoint(x: middle, y: neck)); upper.closeSubpath()
        var lower = Path()
        lower.move(to: CGPoint(x: middle, y: neck)); lower.addLine(to: CGPoint(x: right, y: bottom))
        lower.addLine(to: CGPoint(x: left, y: bottom)); lower.closeSubpath()
        context.fill(upper, with: .color(sand.opacity(0.1)))
        context.fill(lower, with: .color(sand.opacity(0.1)))
        var topFill = context
        topFill.clip(to: upper)
        let upperHeight = (neck - top) * sqrt(1 - p)
        topFill.fill(Path(CGRect(x: left, y: neck - upperHeight, width: right - left, height: upperHeight)), with: .color(sand))
        var bottomFill = context
        bottomFill.clip(to: lower)
        let lowerHeight = (bottom - neck) * (1 - sqrt(1 - p))
        bottomFill.fill(Path(CGRect(x: left, y: bottom - lowerHeight, width: right - left, height: lowerHeight)), with: .color(sand))
        if flowing && p < 1 {
          let y = neck + phase * max(0, bottom - lowerHeight - neck)
          bottomFill.fill(Path(ellipseIn: CGRect(x: middle - 0.8, y: y, width: 1.6, height: 2)), with: .color(sand))
        }
        context.stroke(upper, with: .color(ink.opacity(0.8)), lineWidth: 1.2)
        context.stroke(lower, with: .color(ink.opacity(0.8)), lineWidth: 1.2)
        var caps = Path()
        caps.move(to: CGPoint(x: 2, y: 1)); caps.addLine(to: CGPoint(x: size.width - 2, y: 1))
        caps.move(to: CGPoint(x: 2, y: size.height - 1)); caps.addLine(to: CGPoint(x: size.width - 2, y: size.height - 1))
        context.stroke(caps, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
      }
    }
  }
}

struct ExpiryReasonView: View {
  @ObservedObject var model: AppModel
  let task: PlanTask
  @State private var reason = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(UIStrings.text("说明原因")).font(.title2)
      Text(task.title).font(.headline)
      Text(UIStrings.text("已过期任务不能标记完成或评分，请说明原因。")).font(.callout).foregroundStyle(.secondary)
      TextEditor(text: $reason).frame(height: 140).padding(6)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.3)))
      HStack {
        Button(UIStrings.text("取消")) { model.reviewID = nil }
        Spacer()
        Button(UIStrings.text("保存")) { model.saveExpiryReason(id: task.id, reason: reason) }
      }
    }.padding(24).frame(width: 440)
      .onAppear { reason = task.expiryReason ?? "" }
  }
}
