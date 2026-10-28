import Foundation

/// UI copy is independent of character speech and user-authored content.
public enum UIStrings {
  public static var language: String {
    get { UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "zh" }
    set { UserDefaults.standard.set(newValue, forKey: "interfaceLanguage") }
  }
  public static let translations: [String: [String: String]] = {
    let bundle: Bundle
    if let url = Bundle.main.url(forResource: "StillWithYou_StillWithYouCore", withExtension: "bundle"), let resource = Bundle(url: url) { bundle = resource }
    else { bundle = .module }
    guard let url = bundle.url(forResource: "ui-translations", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [:] }
    return (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
  }()
  public static func text<T>(_ value: T) -> String {
    let source = String(describing: value)
    guard language != "zh", let table = translations[language] else { return source }
    if let translated = table[source] { return translated }
    for key in table.keys.sorted() where key.contains("{0}") {
      var pattern = NSRegularExpression.escapedPattern(for: key)
      for index in 0...5 {
        pattern = pattern.replacingOccurrences(of: NSRegularExpression.escapedPattern(for: "{\(index)}"), with: "(.+?)")
      }
      guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "$"),
        let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else { continue }
      var result = table[key] ?? key
      for index in 1..<match.numberOfRanges {
        if let range = Range(match.range(at: index), in: source) {
          result = result.replacingOccurrences(of: "{\(index - 1)}", with: String(source[range]))
        }
      }
      return result
    }
    return source
  }
}
