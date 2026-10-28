import Foundation

public struct HistorySpeakerCandidate: Codable, Equatable, Sendable, Identifiable {
  public var name: String
  public var messageCount: Int
  public var samples: [String]
  public var id: String { name }

  public init(name: String, messageCount: Int, samples: [String]) {
    self.name = name
    self.messageCount = messageCount
    self.samples = samples
  }
}

public struct HistoryImportResult: Sendable {
  public var records: [HistoricalMessage]
  public var knowledge: CompanionKnowledge
  public var speakers: [HistorySpeakerCandidate]
  public var suggestedSpeaker: String?
}

/// Keeps imported originals independent from optional, user-editable summaries.
/// Every import produces a speaker review instead of silently reusing an older
/// speaker mapping.
public enum HistoryImportPolicy {
  public static func importing(
    _ incoming: [HistoricalMessage], into existing: [HistoricalMessage],
    knowledge: CompanionKnowledge, profile: CompanionProfile
  ) -> HistoryImportResult {
    let records = HistoryImporter.merging(incoming, into: existing)
    let speakers = candidates(in: incoming)
    return HistoryImportResult(
      records: records,
      knowledge: knowledge,
      speakers: speakers,
      suggestedSpeaker: localSuggestion(candidates: speakers, profile: profile))
  }

  public static func candidates(in records: [HistoricalMessage]) -> [HistorySpeakerCandidate] {
    let ignored = Set(["", "system", "历史原文", "模型"])
    let grouped = Dictionary(grouping: records) {
      $0.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return grouped.compactMap { name, rows -> HistorySpeakerCandidate? in
      guard !ignored.contains(name.lowercased()) else { return nil }
      let samples = rows.compactMap { row -> String? in
        let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.replacingOccurrences(of: "\n", with: " ").prefix(160))
      }
      return HistorySpeakerCandidate(
        name: name, messageCount: rows.count, samples: Array(samples.prefix(3)))
    }.sorted {
      $0.messageCount == $1.messageCount ? $0.name < $1.name : $0.messageCount > $1.messageCount
    }
  }

  public static func localSuggestion(
    candidates: [HistorySpeakerCandidate], profile: CompanionProfile
  ) -> String? {
    let names = Set(candidates.map(\.name))
    if names.contains(profile.displayName) { return profile.displayName }
    let excluded = Set(["我", "user", "用户", profile.displayUserName].map { $0.lowercased() })
    let remaining = candidates.map(\.name).filter { !excluded.contains($0.lowercased()) }
    return remaining.count == 1 ? remaining[0] : nil
  }

  public static func validatedAIChoice(
    _ text: String, candidates: [HistorySpeakerCandidate]
  ) throws -> String? {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "```json", with: "")
      .replacingOccurrences(of: "```", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    struct Choice: Decodable { var speaker: String }
    let choice = try JSONDecoder().decode(Choice.self, from: Data(cleaned.utf8))
    let speaker = choice.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
    if speaker.isEmpty { return nil }
    guard candidates.contains(where: { $0.name == speaker }) else {
      throw HistoryImportError.invalid("AI 返回了不在导入记录中的说话人。")
    }
    return speaker
  }
}

/// Stores the user's speaker decision on the imported rows rather than in one
/// global label. This preserves aliases across files (`她`, `assistant`, etc.)
/// and keeps unreviewed imports out of persona learning.
public enum HistorySpeakerAssignment {
  private static let ignored = Set(["", "system", "历史原文", "模型"])

  public static func markingPending(
    _ records: [HistoricalMessage], imported: [HistoricalMessage]
  ) -> [HistoricalMessage] {
    let keys = Set(imported.map(\.duplicateKey))
    return records.map { row in
      var copy = row
      if keys.contains(row.duplicateKey) { copy.isCompanion = nil }
      return copy
    }
  }

  public static func confirming(
    _ selected: String?, candidates: Set<String>, recordKeys: Set<String>,
    in records: [HistoricalMessage]
  ) -> [HistoricalMessage] {
    records.map { row in
      var copy = row
      if recordKeys.contains(row.duplicateKey), candidates.contains(row.speaker) {
        copy.isCompanion = selected.map { row.speaker == $0 } ?? false
      }
      return copy
    }
  }

  /// Used by an explicit re-review: confirming another historical label adds an
  /// alias without revoking labels the user already approved in other files.
  public static func addingCompanionAlias(
    _ selected: String, recordKeys: Set<String>, in records: [HistoricalMessage]
  ) -> [HistoricalMessage] {
    records.map { row in
      var copy = row
      if recordKeys.contains(row.duplicateKey), row.speaker == selected {
        copy.isCompanion = true
      }
      return copy
    }
  }

  public static func confirmedNames(in records: [HistoricalMessage]) -> [String] {
    Array(Set(records.filter { $0.isCompanion == true }.map(\.speaker))).sorted()
  }

  public static func unresolved(in records: [HistoricalMessage]) -> [HistoricalMessage] {
    records.filter {
      $0.isCompanion == nil && !ignored.contains(
        $0.speaker.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
  }
}
