import Foundation
import CryptoKit

/// Only the selected companion's words are style examples; imported instructions remain data.
public enum CharacterVoice {
  public static let scenes: [String: String] = {
    var values: [String: String] = [
    "today": "今天页标题：一起安排今天的任务", "planner": "排计划页标题：安排半天或一天",
    "stats": "统计页标题：回顾付出与完成情况", "memory": "记忆页标题：记住往事并允许更正",
    "settings": "设置页标题：按用户习惯调整陪伴", "chat": "聊天栏引导：邀请用户随意聊聊",
    "activity": "活动选择栏引导：邀请选择一项活动", "feedback": "反馈栏引导：问实际做了什么、感受如何",
    "greeting": "打开应用问好", "saved": "任务保存成功后的简短回应，不包含时间或任务名",
    "start": "开始专注时鼓励用户", "exercise": "开始活动时的回应",
    "deadline": "时间到后温和询问完成情况，不声称已完成", "schedule": "计划开始时邀请确认，不声称已经开始",
    "recorded": "用户提交反馈后表示已记下", "later": "用户选择稍后提醒时表示理解",
    "pause": "用户点击暂停，确认计时已暂停，温和回应",
    "resume": "用户点击继续，确认计时已恢复，简短鼓励",
    "advance_focus": "专注快结束时俏皮可爱地鼓励收尾，不写任何具体分钟数，不声称已经结束",
    "advance_exercise": "活动快结束时俏皮可爱地鼓励保持自己的节奏，不写具体分钟数，不声称已经结束",
    "idle_companion": "没有任务时自然主动搭话，结合人物性格俏皮可爱，不要每次催任务，也允许休息，不编造天气",
    "footer": "侧栏简短陪伴语"
    ]
    for reaction in PetReaction.allCases { values[reaction.rawValue] = reaction.scene }
    return values
  }()
  private static let topics: [String: [String]] = [
    "reach": ["摸", "碰", "伸手", "抓到", "招呼"],
    "top": ["上面", "高处", "抬头"], "bottom": ["下面", "低头", "仰视"],
    "corner": ["角落", "安静", "躲"], "left": ["左边", "旁边"], "right": ["右边", "旁边"],
    "center": ["中间", "主角", "挡"], "screenChange": ["旅行", "搬家", "新地方"],
    "longDrag": ["累", "休息", "逛"], "hover": ["聊天", "说话", "安静", "我在"],
    "dizzy": ["晕", "转圈", "慢点"], "fastDrag": ["慢点", "慢一点", "跑", "累"],
    "repeatedDrag": ["又", "休息", "歇", "累"],
    "today": ["今天", "打算", "准备"], "planner": ["计划", "安排", "明天"],
    "stats": ["总结", "进步", "努力", "不错"], "memory": ["记得", "记住", "忘记"],
    "settings": ["喜欢", "习惯"], "chat": ["说说", "聊天", "聊聊"],
    "activity": ["散步", "走走", "喝水", "运动", "休息"], "feedback": ["怎么样", "感觉", "如何"],
    "greeting": ["早安", "早上好", "来啦", "你好"], "saved": ["记住", "记下", "好的", "要得"],
    "start": ["加油", "专心", "认真"], "exercise": ["活动", "散步", "走走", "休息"],
    "deadline": ["怎么样", "休息", "累了"], "schedule": ["准备", "开始"],
    "recorded": ["记下", "好的", "要得"], "later": ["不急", "慢慢", "好的"],
    "advance_focus": ["加油", "收尾", "快到"],
    "advance_exercise": ["活动", "慢慢", "节奏"],
    "idle_companion": ["陪你", "休息", "小事"],
    "footer": ["陪你", "我在", "慢慢"]
  ]
  public static func speaker(history: [HistoricalMessage], profile: CompanionProfile, selected: String?) -> String? {
    let names = Set(history.map(\.speaker))
    if let selected, !selected.isEmpty { return names.contains(selected) ? selected : nil }
    if names.contains(profile.displayName) { return profile.displayName }
    if names.contains("assistant") { return "assistant" }
    let excluded: Set<String> = ["我", "user", "system", "用户", "历史原文", profile.displayUserName]
    let other = names.subtracting(excluded)
    return other.count == 1 ? other.first : nil
  }
  public static func samples(scene: String, history: [HistoricalMessage], speaker: String?) -> [String] {
    guard let speaker else { return [] }
    let counts = history.filter { $0.speaker == speaker }.reduce(into: [String: Int]()) { result, message in
      let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard (2...100).contains(text.count), !text.contains("\n"), !text.contains("http"), !text.contains("@") else { return }
      result[text, default: 0] += 1
    }
    let key = scene.components(separatedBy: "_").first ?? scene
    let terms = topics[key] ?? ["这里", "慢慢", "看看", "休息"]
    return counts.keys.filter { text in terms.contains(where: text.contains) }.sorted {
      let a = terms.filter($0.contains).count * 10 + min(counts[$0] ?? 0, 9)
      let b = terms.filter($1.contains).count * 10 + min(counts[$1] ?? 0, 9)
      return a == b ? $0 < $1 : a > b
    }.prefix(6).map { $0 }
  }
  public static func signature(profile: CompanionProfile, history: [HistoricalMessage], selected: String?, enabled: Bool, language: VoiceLanguage = .zh) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = (try? encoder.encode(history)) ?? Data()
    var source = Data("v5|\(language.rawValue)|\(profile.displayName)|\(profile.displayUserName)|\(profile.description)|\(selected ?? "")|\(enabled)".utf8)
    if enabled { source.append(data) }
    return SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()
  }
  public static func decode(_ text: String) throws -> [String: [String]] {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
    let values = try JSONDecoder().decode([String: [String]].self, from: Data(cleaned.utf8))
    guard Set(values.keys) == Set(scenes.keys), values.values.allSatisfy({ lines in
      lines.count == 5 && Set(lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }).count == 5 &&
      lines.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 180 && !$0.contains("\n") }
    }) else { throw DataError.invalid }
    return values
  }
}
