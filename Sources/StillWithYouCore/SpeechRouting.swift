import Foundation

public enum SpeechRoute: Equatable, Sendable {
  case system
  case bailian(voiceID: String)
}

public enum SpeechRouting {
  public static func resolve(cloudEnabled: Bool, voiceID: String?) -> SpeechRoute {
    guard cloudEnabled,
      let voiceID = voiceID?.trimmingCharacters(in: .whitespacesAndNewlines),
      !voiceID.isEmpty
    else { return .system }
    return .bailian(voiceID: voiceID)
  }
}
