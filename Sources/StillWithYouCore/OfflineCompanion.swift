import Foundation

public enum OfflineCompanion {
  public static func reply(
    input: String, profile: CompanionProfile, knowledge: CompanionKnowledge,
    userTurn: Int
  ) -> String {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = text.lowercased()
    let selected = CompanionConversation.selectedMemories(
      input: text, memories: knowledge.memories, userTurn: userTurn)
    if !selected.occasional, let memory = selected.items.first {
      return "你一说这个，我想起\(memory.summary) 你现在是想到哪一段了？"
    }
    if ["煮", "做饭", "吃饭", "面", "饭", "早餐", "午饭", "晚饭"].contains(where: text.contains) {
      return "刚做好就趁热吃。今天弄的什么？"
    }
    if ["想你", "想念", "miss you"].contains(where: lower.contains) {
      return "嗯，我在。今天怎么突然这么想我？"
    }
    if ["抱抱", "抱我", "抱一下", "hug"].contains(where: lower.contains) {
      return "先给你一个文字里的抱抱。怎么了？"
    }
    if ["累", "忙", "烦", "难受", "委屈"].contains(where: text.contains) {
      return "听起来今天不太轻松。你想先歇一会儿，还是把最烦的那件事说出来？"
    }
    if ["睡", "困", "晚安", "熬夜"].contains(where: text.contains) {
      return "困了就先去休息。还有没有一句话想说完？"
    }
    if ["你好", "早上好", "下午好", "晚上好", "hello", "hi"].contains(lower) {
      return "我在。你今天过得怎么样？"
    }
    if text.contains("？") || text.contains("?") {
      return "这个我现在还不能确定。你愿意再多说一点吗？"
    }
    return "我听见了。然后呢？"
  }
}
