import Foundation

public enum AIProviderPreset: String, CaseIterable, Codable, Sendable {
  case deepseek
  case openai
  case openAICompatible = "openai-compatible"

  public var title: String {
    switch self {
    case .deepseek: return "DeepSeek"
    case .openai: return "OpenAI"
    case .openAICompatible: return "OpenAI 兼容服务"
    }
  }
}

public extension Preferences {
  var resolvedAIProvider: AIProviderPreset {
    AIProviderPreset(rawValue: aiProvider ?? "deepseek") ?? .deepseek
  }

  var resolvedAIEndpoint: URL {
    if resolvedAIProvider == .openAICompatible,
      let value = aiEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines),
      let url = URL(string: value), !value.isEmpty
    { return url }
    switch resolvedAIProvider {
    case .openai:
      return URL(string: "https://api.openai.com/v1/chat/completions")!
    case .deepseek, .openAICompatible:
      return URL(string: "https://api.deepseek.com/chat/completions")!
    }
  }
}
