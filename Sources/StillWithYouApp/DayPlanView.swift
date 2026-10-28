import SwiftUI
import StillWithYouCore

final class DayPlanDraft: ObservableObject {
  @Published var date = Date()
  @Published var scope = "上午"
  @Published var morningStart = Date()
  @Published var morningEnd = Date()
  @Published var afternoonStart = Date()
  @Published var afternoonEnd = Date()
  @Published var focus = 45
  @Published var activity = 15
  @Published var tasks: [PlanTask] = []
  @Published var generatedKey = ""
  @Published var error = ""
}

struct DayPlanView: View {
  @ObservedObject var model: AppModel
  @ObservedObject private var draft: DayPlanDraft
  @State private var currentTime = Date()
  init(model: AppModel) {
    self.model = model
    self.draft = model.dayPlanDraft
  }
  private var morningAvailable: Bool { clock(12) > currentTime }
  private var dayEnd: Date { Calendar.current.dateInterval(of: .day, for: draft.date)!.end }
  private var afternoonAvailable: Bool { dayEnd > currentTime }
  private var morning: Bool { draft.scope != "下午" && morningAvailable }
  private var afternoon: Bool { draft.scope != "上午" && afternoonAvailable }
  private var ranges: [(Date, Date)] {
    (morning ? [(draft.morningStart, draft.morningEnd)] : []) + (afternoon ? [(draft.afternoonStart, draft.afternoonEnd)] : [])
  }
  private var schedulableRanges: [(Date, Date)] {
    ranges.compactMap { start, end in
      var first = start
      if Calendar.current.isDate(draft.date, inSameDayAs: currentTime), first < currentTime {
        first = Date(timeIntervalSince1970: ceil(currentTime.timeIntervalSince1970 / 60) * 60)
      }
      return first < end ? (first, end) : nil
    }
  }
  private var key: String { "\(Day.key(draft.date))|\(draft.scope)|\(ranges.map { [$0.0.timeIntervalSince1970, $0.1.timeIntervalSince1970] })|\(draft.focus)|\(draft.activity)" }
  private var stale: Bool { key != draft.generatedKey }
  private var activityReady: Bool { draft.tasks.allSatisfy { $0.exerciseMinutes == 0 || !$0.exercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
  private var canSave: Bool { activityReady && !draft.tasks.isEmpty && !stale && !invalidRange && draft.tasks.allSatisfy { $0.plannedStart.map { DayPlanner.canSchedule(start: $0, now: currentTime) } ?? false } }
  private func clock(_ hour: Int) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: draft.date)!
  }
  private func defaults() {
    let now = Date()
    let today = Day.key(draft.date) == Day.key(now)
    let rounded = DayPlanner.roundedHour(now)
    draft.morningStart = today && now < clock(12) ? rounded : clock(9)
    draft.morningEnd = clock(12)
    let remaining = DayPlanner.remainingDayRange(day: draft.date, now: now)
    draft.afternoonStart = remaining.start
    draft.afternoonEnd = remaining.end
    draft.error = ""
  }
  private func time(_ value: Date) -> String { value.formatted(date: .omitted, time: .shortened) }
  private var invalidRange: Bool {
    ranges.isEmpty || schedulableRanges.isEmpty || ranges.contains { $0.1 <= $0.0 || Day.key($0.0) != Day.key(draft.date) || $0.1 > dayEnd }
      || (morning && afternoon && draft.morningEnd > draft.afternoonStart)
  }
  private func generate() {
    currentTime = Date()
    guard !invalidRange else { draft.error = "不能安排已经过去的开始时间。请调整到未来时段，结束时间须晚于开始时间。"; return }
    let starts = schedulableRanges.flatMap { DayPlanner.slots(start: $0.0, end: $0.1, focus: draft.focus, activity: draft.activity) }
    guard !starts.isEmpty else { draft.error = "这个时间范围放不下一整段，请调整开始、结束时间或每段时长。"; return }
    let old = draft.tasks
    let overlapsOldSlots = starts.contains { start in old.contains { $0.plannedStart == start } }
    draft.tasks = starts.enumerated().map { index, start in
      let previous = old.first { $0.plannedStart == start } ?? (!overlapsOldSlots && index < old.count ? old[index] : nil)
      var task = PlanTask(day: Day.key(draft.date), title: previous?.title ?? "", focusMinutes: draft.focus,
        exerciseMinutes: draft.activity, exercise: previous?.exercise ?? "")
      task.plannedStart = start
      return task
    }
    draft.generatedKey = key
    draft.error = ""
  }
  private func ready(_ task: PlanTask) -> Bool {
    !stale && (task.exerciseMinutes == 0 || !task.exercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && (task.plannedStart.map { DayPlanner.canSchedule(start: $0, now: currentTime) } ?? false)
  }
  private func readyToStart(_ task: PlanTask) -> Bool {
    !stale && Day.key(draft.date) == Day.key(currentTime) && task.day == Day.key(currentTime)
      && (task.exerciseMinutes == 0 || !task.exercise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      && model.state.timer == nil
  }
  private func save(startNow: Bool, onlyID: UUID? = nil) {
    currentTime = Date()
    if startNow, let onlyID,
      let index = draft.tasks.firstIndex(where: { $0.id == onlyID }), readyToStart(draft.tasks[index]) {
      // A filled task may sit in the planner until its generated slot passes.
      // Starting it now is explicit, so move its planned start to this moment.
      draft.tasks[index].plannedStart = currentTime
      draft.tasks[index].day = Day.key(currentTime)
    } else {
      guard onlyID.map({ id in draft.tasks.first(where: { $0.id == id }).map { ready($0) } ?? false }) ?? canSave else {
        draft.error = "开始时间已过或时间设置有变化；可重新生成时段，或对当天任务选择“保存并启动”立即开始。"
        return
      }
    }
    for index in draft.tasks.indices {
      if draft.tasks[index].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        draft.tasks[index].title = "专注任务 \(index + 1)"
      }
    }
    // Avoid accidental double booking of existing scheduled plans; unrelated unscheduled tasks remain.
    let selected = draft.tasks.filter { onlyID == nil || $0.id == onlyID }
    let conflict = selected.contains { candidate in
      guard let start = candidate.plannedStart else { return false }
      let end = start.addingTimeInterval(Double(candidate.focusMinutes + candidate.exerciseMinutes) * 60)
      return model.state.tasks.contains { existing in
        guard !existing.cancelled, existing.deletedAt == nil, let other = existing.plannedStart else { return false }
        let otherEnd = other.addingTimeInterval(Double(existing.focusMinutes + existing.exerciseMinutes) * 60)
        return start < otherEnd && other < end
      }
    }
    guard !conflict else { draft.error = "这些时段与已保存的计划重叠。请调整时间，或先在今天页取消旧计划。"; return }
    if model.saveDayPlan(selected, startNow: startNow) {
      let savedIDs = Set(selected.map(\.id))
      draft.tasks.removeAll { savedIDs.contains($0.id) }
      draft.error = ""
      if draft.tasks.isEmpty { draft.generatedKey = ""; model.tab = "今天" }
    }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        Text(model.voice("planner", "给半天，或一整天，排好节奏。")).font(.system(size: 26, weight: .medium, design: .serif))
        Text(UIStrings.text("默认按电脑今天的日期排计划。先生成时段，再为每段选择或填写活动内容，保存后加入对应日期的任务列表；计时由你手动启动。"))
          .foregroundStyle(.secondary)
        Card {
          HStack {
            DatePicker(UIStrings.text("计划日期"), selection: $draft.date, in: Calendar.current.startOfDay(for: currentTime)..., displayedComponents: .date)
              .onChange(of: draft.date) { _, _ in defaults() }
            HStack {
              ForEach(["上午", "下午", "全天"], id: \.self) { value in
                Button(UIStrings.text(value)) { draft.scope = value }
                  .tint(draft.scope == value ? Color.lake : Color.secondary)
                  .disabled(value == "上午" ? !morningAvailable : value == "下午" ? !afternoonAvailable : (!morningAvailable && !afternoonAvailable))
              }
            }.buttonStyle(.bordered).frame(width: 250)

          }
          if morning {
            HStack {
              Text(UIStrings.text("上午")).frame(width: 44, alignment: .leading)
              DatePicker(UIStrings.text("开始"), selection: $draft.morningStart, in: currentTime..., displayedComponents: .hourAndMinute)
              DatePicker(UIStrings.text("结束"), selection: $draft.morningEnd, displayedComponents: .hourAndMinute)
            }
          }
          if afternoon {
            HStack {
              Text(UIStrings.text("下午 / 晚上")).frame(width: 80, alignment: .leading)
              DatePicker(UIStrings.text("开始"), selection: $draft.afternoonStart, in: currentTime..., displayedComponents: .hourAndMinute)
              DatePicker(UIStrings.text("结束"), selection: Binding(get: { draft.afternoonEnd }, set: { value in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
                draft.afternoonEnd = parts.hour == 0 && parts.minute == 0 ? dayEnd : Calendar.current.date(bySettingHour: parts.hour ?? 18, minute: parts.minute ?? 0, second: 0, of: draft.date)!
              }), displayedComponents: .hourAndMinute)
              if draft.afternoonEnd == dayEnd { Text("24:00").font(.caption).foregroundStyle(.secondary) }
            }
          }
          HStack {
            Picker(UIStrings.text("每段专注"), selection: $draft.focus) { ForEach([15, 30, 45], id: \.self) { Text(UIStrings.text("\($0) 分钟")) } }
            Picker(UIStrings.text("每段活动"), selection: $draft.activity) { ForEach(0...15, id: \.self) { Text(UIStrings.text($0 == 0 ? "不安排" : "\($0) 分钟")) } }
          }
          Text(UIStrings.text("默认 45＋15 分钟。当天上午按当前时间向后取整；下午默认从 14:00 开始，已过 14:00 则取下一个整点。午间不排任务。18:00 只是默认结束时间，晚上仍可安排至 24:00。"))
            .font(.caption).foregroundStyle(.secondary)
          HStack {
            Button(UIStrings.text(draft.tasks.isEmpty ? "生成时段" : "重新生成时段")) { generate() }.buttonStyle(.borderedProminent).disabled(invalidRange)
          }
          if !morningAvailable { Text(UIStrings.text("所选日期的上午已经过去，不可再安排；全天模式只安排剩余时段。")).font(.caption).foregroundStyle(.secondary) }
          if invalidRange { Text(UIStrings.text("开始时间已过或时间范围无效，请修改时间；可安排至当天 24:00。")).font(.caption).foregroundStyle(.orange) }
          if !draft.error.isEmpty { Text(UIStrings.text(draft.error)).foregroundStyle(.red).font(.callout) }
        }
        if !draft.tasks.isEmpty {
          if stale { Text(UIStrings.text("时间设置已修改，请重新生成时段。填写过的任务内容会尽量保留。")).foregroundStyle(.orange) }
          else {
            let free = ranges.reduce(0) { total, range in
              total + Int(range.1.timeIntervalSince(range.0) / 60) % (draft.focus + draft.activity)
            }
            Text(UIStrings.text("共 \(draft.tasks.count) 段 · 专注 \(draft.tasks.count * draft.focus) 分钟 · 活动 \(draft.tasks.count * draft.activity) 分钟" + (free > 0 ? " · 尾部共 \(free) 分钟留作自由安排" : "")))
              .font(.headline)
          }
          ForEach($draft.tasks) { $task in
            Card {
              if let start = task.plannedStart {
                Text(UIStrings.text("\(time(start)) – \(time(start.addingTimeInterval(Double(task.focusMinutes + task.exerciseMinutes) * 60)))"))
                  .font(.headline).monospacedDigit()
                Text(UIStrings.text("专注至 \(time(start.addingTimeInterval(Double(task.focusMinutes) * 60)))" + (task.exerciseMinutes > 0 ? "，随后活动 \(task.exerciseMinutes) 分钟" : "，本段不安排活动")))
                  .font(.caption).foregroundStyle(.secondary)
              }
              TextField(UIStrings.text("这一段要完成什么？"), text: $task.title).textFieldStyle(.roundedBorder)
              if task.exerciseMinutes > 0 { ActivityInput(model: model, exercise: $task.exercise) }
              HStack {
                Button(UIStrings.text("保存")) { save(startNow: false, onlyID: task.id) }
                  .buttonStyle(.borderedProminent).disabled(!ready(task))
                Button(UIStrings.text("保存并启动")) { save(startNow: true, onlyID: task.id) }
                  .disabled(!readyToStart(task))
                Text(UIStrings.text("保存并启动会立即开始首项；仅保存不会开始计时。"))
                  .font(.caption).foregroundStyle(.secondary)
              }
            }
          }
          Card {
            HStack {
              Button(UIStrings.text("保存并启动首项")) { save(startNow: true) }.buttonStyle(.borderedProminent)
                .disabled(!canSave || model.state.timer != nil || Day.key(draft.date) != Day.key())
              Button(UIStrings.text("加入当天任务")) { save(startNow: false) }.disabled(!canSave)
              Text(UIStrings.text("保存并启动会立即开始首项；仅保存不会开始计时。")).font(.caption).foregroundStyle(.secondary)
            }
            if !canSave { Text(UIStrings.text(stale ? "请先重新生成时段。" : !activityReady ? "请为每一段选择或填写活动内容。" : "开始时间已过，请调整时间后刷新预览。")).font(.caption).foregroundStyle(.secondary) }
          }
        }
      }.padding(30)
    }.onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { currentTime = $0 }
    .onAppear {
      currentTime = Date()
      if draft.generatedKey.isEmpty {
        draft.date = Date()
        let hour = Calendar.current.component(.hour, from: currentTime)
        draft.scope = hour < 12 ? "上午" : hour < 18 ? "下午" : "全天"
        defaults()
        generate()
      }
    }
  }
}
