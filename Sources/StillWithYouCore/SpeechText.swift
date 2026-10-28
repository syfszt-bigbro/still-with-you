import Foundation

public enum SpeechText {
  /// Expand countdown notation only for speech; the chat keeps its original formatting.
  public static func expandingCountdowns(_ text: String) -> String {
    let pattern = #"(?<![\d:：])(\d{1,3})[:：]([0-5]\d)(?:[:：]([0-5]\d))?(?![\d:：])"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
    let source = text as NSString
    var result = text
    for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
      let a = Int(source.substring(with: match.range(at: 1))) ?? 0
      let b = Int(source.substring(with: match.range(at: 2))) ?? 0
      let replacement: String
      if match.range(at: 3).location != NSNotFound {
        let c = Int(source.substring(with: match.range(at: 3))) ?? 0
        replacement = "\(a)小时\(b)分\(c)秒"
      } else {
        // Explicit clock-time phrases are not countdowns.
        let prefix = source.substring(to: match.range.location)
        if ["现在是", "时间是", "当前时间", "北京时间", "开始于", "结束于"].contains(where: { prefix.hasSuffix($0) || prefix.hasSuffix($0 + " ") }) { continue }
        replacement = "\(a)分\(b)秒"
      }
      if let range = Range(match.range, in: result) { result.replaceSubrange(range, with: replacement) }
    }
    return result
  }
}
