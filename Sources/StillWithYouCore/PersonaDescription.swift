import Foundation

public struct PersonaDescriptionSample: Codable, Equatable, Sendable {
  public var timestamp: String
  public var speaker: String
  public var text: String

  public init(timestamp: String, speaker: String, text: String) {
    self.timestamp = timestamp
    self.speaker = speaker
    self.text = text
  }
}

public struct PersonaDescriptionDraft: Codable, Equatable, Sendable {
  public var description: String

  public init(description: String) {
    self.description = description
  }
}

public enum PersonaDescriptionError: LocalizedError {
  case noConfirmedRecords
  case invalidResponse

  public var errorDescription: String? {
    switch self {
    case .noConfirmedRecords:
      return "还没有确认属于对方的历史原文。请先导入记录并确认说话人。"
    case .invalidResponse:
      return "AI 没有返回可确认的人物描述，请重试或手动填写。"
    }
  }
}

public enum PersonaDescriptionPolicy {
  /// Select only rows the user explicitly confirmed as the companion. Samples
  /// are spread across the full timeline instead of taking only the beginning.
  public static func samples(
    from history: [HistoricalMessage], limit: Int = 120,
    totalCharacterLimit: Int = 24_000
  ) throws -> [PersonaDescriptionSample] {
    let eligible = history.filter {
      $0.isCompanion == true
        && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    guard !eligible.isEmpty else { throw PersonaDescriptionError.noConfirmedRecords }

    let count = min(max(1, limit), eligible.count)
    let selected: [HistoricalMessage]
    if eligible.count <= count {
      selected = eligible
    } else if count == 1 {
      selected = [eligible[eligible.count / 2]]
    } else {
      selected = (0..<count).map { offset in
        let position = Double(offset) * Double(eligible.count - 1) / Double(count - 1)
        return eligible[Int(position.rounded())]
      }
    }

    var remaining = max(1, totalCharacterLimit)
    var result: [PersonaDescriptionSample] = []
    for record in selected {
      guard remaining > 0 else { break }
      let clean = record.text.trimmingCharacters(in: .whitespacesAndNewlines)
      let clipped = String(clean.prefix(min(300, remaining)))
      guard !clipped.isEmpty else { continue }
      result.append(PersonaDescriptionSample(
        timestamp: String(record.timestamp.prefix(80)),
        speaker: String(record.speaker.prefix(80)), text: clipped))
      remaining -= clipped.count
    }
    guard !result.isEmpty else { throw PersonaDescriptionError.noConfirmedRecords }
    return result
  }

  public static func decode(_ response: String) throws -> PersonaDescriptionDraft {
    guard let start = response.firstIndex(of: "{"),
      let end = response.lastIndex(of: "}"), start <= end else {
      throw PersonaDescriptionError.invalidResponse
    }
    let data = Data(response[start...end].utf8)
    guard let decoded = try? JSONDecoder().decode(PersonaDescriptionDraft.self, from: data) else {
      throw PersonaDescriptionError.invalidResponse
    }
    let clean = decoded.description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty, clean.count <= 4000 else {
      throw PersonaDescriptionError.invalidResponse
    }
    return PersonaDescriptionDraft(description: clean)
  }
}
