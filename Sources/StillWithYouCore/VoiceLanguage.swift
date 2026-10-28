import Foundation

public enum VoiceLanguage: String, Codable, CaseIterable, Sendable {
  case zh, ja, ko, en, fr, ru, pt, es, ar
  public var label: String {
    switch self {
    case .zh: return "中文"; case .ja: return "日本語"; case .ko: return "한국어"
    case .en: return "English"; case .fr: return "Français"; case .ru: return "Русский"
    case .pt: return "Português"; case .es: return "Español"; case .ar: return "العربية"
    }
  }
  public var speechCode: String {
    switch self {
    case .zh: return "zh-CN"; case .ja: return "ja-JP"; case .ko: return "ko-KR"
    case .en: return "en-US"; case .fr: return "fr-FR"; case .ru: return "ru-RU"
    case .pt: return "pt-PT"; case .es: return "es-ES"; case .ar: return "ar-SA"
    }
  }
  public var instruction: String { "所有回复使用\(label)，保持人物性格，将历史口头禅自然转述为该语言，不夹杂中文模板。用户自填名字和任务原文保持原样。" }
  public func format(_ key: String, _ values: [String: String] = [:]) -> String {
    var result = VoiceCatalog.templates[rawValue]?[key] ?? VoiceCatalog.templates["en"]?[key] ?? key
    for (key, value) in values { result = result.replacingOccurrences(of: "{" + key + "}", with: value) }
    return result
  }
}

public struct VoicePack: Codable, Sendable {
  public var signature: String
  public var lines: [String: [String]]
  public init(signature: String, lines: [String: [String]]) { self.signature = signature; self.lines = lines }
}

/// Each phrase is used once per shuffle, with no repetition at the shuffle boundary.
public struct PhraseDeck {
  private var remaining: [String: [String]] = [:]
  private var previous: [String: String] = [:]
  public init() {}
  public mutating func next(key: String, choices: [String]) -> String {
    let unique = Array(Set(choices)).sorted()
    guard !unique.isEmpty else { return "" }
    var deck = remaining[key] ?? []
    if deck.isEmpty || !Set(deck).isSubset(of: Set(unique)) {
      deck = unique.shuffled()
      if deck.count > 1, deck.last == previous[key] { deck.swapAt(0, deck.count - 1) }
    }
    let line = deck.removeLast()
    remaining[key] = deck; previous[key] = line
    return line
  }
}

public enum VoiceCatalog {
  private static var resources: Bundle {
    if let url = Bundle.main.url(forResource: "StillWithYou_StillWithYouCore", withExtension: "bundle"), let bundle = Bundle(url: url) { return bundle }
    return .module
  }
  public static let reactions: [String: [String: [String]]] = {
    guard let url = resources.url(forResource: "voice-reactions", withExtension: "json"),
      let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([String: [String: [String]]].self, from: data) else { return [:] }
    return values
  }()
  public static let templates: [String: [String: String]] = {
    guard let url = resources.url(forResource: "voice-templates", withExtension: "json"),
      let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
    return values
  }()
}
