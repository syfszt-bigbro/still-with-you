import Foundation

public enum ConversationQualityIssue: String, Codable, CaseIterable, Sendable {
  case empty
  case repeated
  case unrelatedSleep
  case identityOrRelationshipInflation
  case excessiveLength
  case placeholderLeak
  case tooThin
}

public enum ConversationQualityGuard {
  private static func normalized(_ text: String) -> String {
    text.lowercased().filter { $0.isLetter || $0.isNumber }
  }

  public static func issues(
    input: String, reply: String, recentAssistant: [String]
  ) -> [ConversationQualityIssue] {
    let clean = reply.trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.isEmpty { return [.empty] }
    var result: [ConversationQualityIssue] = []
    let key = normalized(clean)
    if recentAssistant.suffix(12).contains(where: { normalized($0) == key }) { result.append(.repeated) }
    if clean.count > 480 || clean.components(separatedBy: .newlines).filter({ !$0.isEmpty }).count > 6 {
      result.append(.excessiveLength)
    }
    if ["...", "…", "……", "。。。"].contains(clean) { result.append(.tooThin) }
    if clean.contains("表情包：") || clean.contains("表情包:") || clean.contains("[sticker") {
      result.append(.placeholderLeak)
    }

    let inputMentionsSleep = ["睡", "困", "醒", "起床", "晚安", "熬夜", "sleep", "tired"].contains {
      input.localizedCaseInsensitiveContains($0)
    }
    if !inputMentionsSleep {
      let sleepTerms = ["去睡觉", "睡觉睡觉", "快睡", "赶紧睡", "先睡"]
      if sleepTerms.contains(where: clean.contains) { result.append(.unrelatedSleep) }
    }

    let inflated = ["我是真人", "我就是本人", "永远陪着你", "永远不会离开你", "我们已经结婚", "我们复合了"]
    if inflated.contains(where: clean.contains) { result.append(.identityOrRelationshipInflation) }
    return result
  }

  public static func rewriteInstruction(for issues: [ConversationQualityIssue]) -> String {
    let names = issues.map(\.rawValue).joined(separator: ", ")
    return "上一版回复未通过质量检查（\(names)）。请重新回答用户眼前的话：换一种自然表达，不重复近期回复；不只回省略号，不输出‘表情包’等占位标签；不无关地劝睡觉；不冒充真人或夸大关系；默认1—4个短句。只输出新回复。"
  }
}
