import Foundation

public enum MemorySemantics {
  public static var calendar: Calendar {
    var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return c
  }
  public static func category(_ text: String) -> String {
    if ["搬家", "面试", "考试", "出差", "旅行", "开会", "答辩", "生日", "约会", "相亲", "交稿"].contains(where:text.contains) && !["我喜欢", "我不喜欢", "我讨厌", "我偏好"].contains(where:text.hasPrefix) { return "event" }
    if ["今天", "现在", "这会", "今晚", "暂时", "这次"].contains(where: text.contains) { return "temporary" }
    if ["回复", "叫我", "称呼", "陪我", "闲聊", "提醒我"].contains(where: text.contains) { return "relationship" }
    if ["我叫", "我的名字", "我住在", "我来自", "我的职业", "我是做"].contains(where: text.hasPrefix) { return "identity" }
    if ["每天", "通常", "习惯", "每周"].contains(where: text.contains) { return "pattern" }
    return "preference"
  }
  public static func eventKey(_ text: String) -> String? {
    let keys = ["搬家", "面试", "考试", "出差", "旅行", "开会", "答辩", "生日", "约会", "相亲", "交稿"].filter(text.contains)
    return keys.count == 1 ? keys[0] : nil
  }
  public static func key(_ text: String, category: String) -> String? {
    if category == "event" { return eventKey(text).map { "event:" + $0 } }
    guard category != "temporary" else { return nil }
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: .punctuationCharacters)
    for prefix in ["我不再喜欢", "我不喜欢", "我喜欢", "我讨厌", "我偏好"] where cleaned.hasPrefix(prefix) {
      let target = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
      if !target.isEmpty && target.count <= 20 && !target.contains("，") { return "preference:" + target }
    }
    for (prefix, key) in [("我叫", "identity:name"), ("我的名字是", "identity:name"), ("我住在", "identity:residence"), ("叫我", "relationship:address")] where cleaned.hasPrefix(prefix) { return key }
    return nil
  }
  public static func eventStatus(_ text: String) -> String {
    if ["取消", "不去了", "不去面试", "不搬家了", "不用交稿"].contains(where: text.contains) { return "cancelled" }
    if ["完成了", "结束了", "已经考完", "搬完家", "面试完", "交稿了"].contains(where: text.contains) { return "completed" }
    return "planned"
  }
  public static func dueDate(_ text: String, from date: Date) -> Date? {
    let c = calendar, day = c.startOfDay(for: date)
    guard eventKey(text) != nil else { return nil }
    let timeMarkers = ["今天", "今晚", "明天", "后天", "下周", "下星期"].filter(text.contains)
    guard timeMarkers.count <= 1 else { return nil }
    if text.contains("后天") { return c.date(byAdding: .day, value: 2, to: day) }
    if text.contains("明天") { return c.date(byAdding: .day, value: 1, to: day) }
    if text.contains("今天") || text.contains("今晚") { return day }
    let weekdays = ["一":2,"二":3,"三":4,"四":5,"五":6,"六":7,"日":1,"天":1]
    for (word, target) in weekdays where text.contains("下周" + word) || text.contains("下星期" + word) {
      let weekday = c.component(.weekday, from: day)
      let offset = 7 - ((weekday + 5) % 7) + ((target + 5) % 7)
      return c.date(byAdding: .day, value: offset, to: day)
    }
    if let regex = try? NSRegularExpression(pattern: #"(?:(\d{4})年)?(\d{1,2})月(\d{1,2})[日号]"#), let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
      let ns = text as NSString, month = Int(ns.substring(with:m.range(at:2)))!, d = Int(ns.substring(with:m.range(at:3)))!
      let explicitYear = m.range(at:1).location != NSNotFound
      let year = explicitYear ? Int(ns.substring(with:m.range(at:1)))! : c.component(.year, from: date)
      guard let result = c.date(from: DateComponents(year:year,month:month,day:d)), c.component(.month, from:result)==month, c.component(.day, from:result)==d else { return nil }
      if !explicitYear && result < day { return nil }
      return result
    }
    return nil // Ask about vague times; never invent a date.
  }
  public static func label(_ category: String) -> String {
    ["identity":"身份背景","event":"事件","preference":"长期偏好","pattern":"用户自述习惯","relationship":"相处方式","temporary":"临时状态"][category] ?? "用户原话"
  }
}

public enum ConversationContext {
  /// Preserve the current episode, separated by 30-minute gaps, within a bounded budget.
  public static func messages(_ messages: [ChatMessage], limit: Int = 12000) -> [[String:String]] {
    let chats = messages.filter { ["chat","timer_action","reflection_reply"].contains($0.kind) }
    guard let last = chats.last else { return [] }
    var previous = last.date, selected: [ChatMessage] = [], count = 0
    for message in chats.reversed() {
      if !selected.isEmpty && previous.timeIntervalSince(message.date) > 1800 { break }
      guard count + message.content.count <= limit else { break }
      selected.append(message); count += message.content.count; previous = message.date
    }
    return selected.reversed().map { ["role":$0.role,"content":$0.content] }
  }
}

public enum ProgressEvidence {
  public static func summary(tasks: [PlanTask], now: Date = Date()) -> String {
    let cutoff = Day.key(now.addingTimeInterval(-7 * 86400))
    let recent = tasks.filter { !$0.cancelled && $0.deletedAt == nil && $0.day >= cutoff && $0.day <= Day.key(now) }
    let completed = recent.filter { $0.focus.outcome == .done }
    let movements = recent.filter { $0.movement.outcome != .pending }
    let exerciseDone = movements.filter { $0.movement.outcome == .done }
    let groups: [(String,[String])] = [("产品/开发",["产品","代码","开发","软件","设计"]),("学习/阅读",["学习","读","书","课程","考试"]),("工作/写作",["报告","写作","工作","文案","方案"])]
    let themes = groups.compactMap { label, words -> String? in
      let matches = recent.filter { t in words.contains(where:t.title.contains) }
      return matches.isEmpty ? nil : "\(label)：\(matches.count)条计划，\(matches.filter{$0.focus.outcome == .done}.count)条明确完成"
    }
    return "最近7天共\(recent.count)条计划，明确完成专注\(completed.count)条；运动有反馈\(movements.count)条，标记完成\(exerciseDone.count)条，记录实际运动\(Int(exerciseDone.reduce(0){$0+$1.movement.seconds}/60))分钟。未记录不等于没做；评分仅用户自评。主题按标题关键词粗分，可重叠，不是确定的长期目标。\n" + themes.joined(separator:"\n") + "\n最近实际反馈：" + recent.suffix(5).map { "\($0.title)：专注\($0.focus.outcome.title)，活动\($0.exercise)：\($0.movement.outcome.title)，\($0.movement.note)" }.joined(separator:"；")
  }
}
