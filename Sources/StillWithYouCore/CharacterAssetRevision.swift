import Foundation

/// Builds the identity used by the desktop sprite cache.
///
/// A custom character always has the same picker value and file path. Including
/// a content digest ensures regenerating that file is observable immediately,
/// even when the replacement has the same byte count or filesystem timestamp.
public enum CharacterAssetRevision {
  public static func cacheKey(selection: String, customAssetURL: URL) throws -> String {
    guard selection == "custom" else { return selection }
    let data = try Data(contentsOf: customAssetURL, options: [.mappedIfSafe])
    var digest: UInt64 = 1_469_598_103_934_665_603
    for byte in data {
      digest ^= UInt64(byte)
      digest &*= 1_099_511_628_211
    }
    return "custom:\(data.count):\(String(digest, radix: 16))"
  }
}
