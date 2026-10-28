import Foundation

public enum ChatTimerIntent: Equatable {
  case pause, resume, clarify

  /// Parse only the latest user utterance. Never run this on history or AI replies.
  public static func parse(_ input: String) -> ChatTimerIntent? {
    let text = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let resumeWords = ["继续", "恢复", "接着计时", "接着干", "resume"]
    let pauseWords = ["暂停", "停一下", "停一哈", "停一会", "先停", "歇一会", "歇一哈", "pause"]
    guard (resumeWords + pauseWords).contains(where: text.contains) else { return nil }
    if ["如果", "假如", "要是", "怎么", "如何", "为什么", "为何", "啥意思", "什么意思", "刚才", "昨天", "上次", "他说", "她说", "你说", "“", "\"", "how ", "if "].contains(where: text.contains) { return nil }
    if text.range(of: #"(不要|不用|别|莫|不想|不能|不需要|不要再).{0,3}(暂停|继续|恢复|停|歇)|不(暂停|继续|恢复)|don't|do not"#, options: .regularExpression) != nil { return nil }
    let resume = resumeWords.contains(where: text.contains)
    // A paused task is the object of 'resume', not a second pause instruction.
    var actions = text
    for reference in ["之前暂停的任务", "之前暂停的", "暂停的任务", "暂停的计时", "已经暂停的", "已暂停的", "暂停了的"] { actions = actions.replacingOccurrences(of: reference, with: "任务") }
    let pause = pauseWords.contains(where: actions.contains)
    if resume && pause { return .clarify }
    let related = ["任务", "计时", "专注", "工作", "倒计时"].contains(where: text.contains)
    let imperative = ["帮我", "给我", "麻烦", "请", "喊你", "叫你"].contains(where: text.contains)
    if resume && (related || imperative || text.count <= 6 || text == "resume") { return .resume }
    if pause && (related || imperative || text.count <= 8 || text == "pause") { return .pause }
    return nil
  }
}

/// Explicit `启动 + task name` / `开始 + task name` command used to start a
/// named focus task directly from chat.
public enum ChatStartCommand {
  public static func taskName(in input: String) -> String? {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefixes = ["启动", "开始", "start"]
    guard let prefix = prefixes.first(where: { text.lowercased().hasPrefix($0.lowercased()) }) else {
      return nil
    }
    var suffix = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    // Require an explicit delimiter so ordinary conversation such as “开始
    // 怎么安排” is not mistaken for a task title.
    guard let first = suffix.first, "+＋:： \t".contains(first) else { return nil }
    while let first = suffix.first, "+＋:： \t".contains(first) { suffix.removeFirst() }
    suffix = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
    suffix = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "，。.!！?？\"'“”"))
    guard !suffix.isEmpty,
      !["任务", "任务名称", "任务名", "工作", "专注"].contains(suffix.lowercased()),
      !["不要", "别", "不想", "如果", "假如", "怎么", "如何", "为什么"].contains(where: suffix.hasPrefix)
    else { return nil }
    return suffix
  }
}
