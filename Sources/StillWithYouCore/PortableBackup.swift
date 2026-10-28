import Foundation

public struct PortableBackup: Codable, Sendable {
  public var formatVersion: Int
  public var createdAt: Date
  public var state: AppState
  /// Paths are relative to the local `character` directory. JSON encodes Data as base64.
  public var characterFiles: [String: Data]

  public init(
    formatVersion: Int = 1, createdAt: Date = Date(), state: AppState,
    characterFiles: [String: Data] = [:]
  ) {
    self.formatVersion = formatVersion
    self.createdAt = createdAt
    self.state = state
    self.characterFiles = characterFiles
  }

  public func validatedCharacterFiles() throws -> [String: Data] {
    guard formatVersion == 1, characterFiles.count <= 32 else { throw PortableBackupError.invalid }
    var total = 0
    for (path, data) in characterFiles {
      let parts = path.split(separator: "/", omittingEmptySubsequences: false)
      guard !path.hasPrefix("/"), !path.contains("\\"), !parts.contains(".."),
        !parts.contains("."), !parts.contains(""), data.count <= 8 * 1024 * 1024 else {
        throw PortableBackupError.invalid
      }
      total += data.count
      guard total <= 32 * 1024 * 1024 else { throw PortableBackupError.invalid }
    }
    return characterFiles
  }
}

public enum PortableBackupError: Error { case invalid }
