import AppKit
import CryptoKit
import Foundation
import PDFKit
import StillWithYouCore
import Vision

public enum HistoryDocumentImporter {
  public static let supportedExtensions = [
    "txt", "md", "markdown", "json", "jsonl",
    "jpg", "jpeg", "png", "heic", "tif", "tiff",
    "pdf", "doc", "docx", "rtf",
  ]

  private static let textExtensions = Set(["txt", "md", "markdown", "json", "jsonl"])
  private static let imageExtensions = Set(["jpg", "jpeg", "png", "heic", "tif", "tiff"])
  private static let wordExtensions = Set(["doc", "docx", "rtf"])
  private static let textLimit = 10 * 1024 * 1024
  private static let documentLimit = 50 * 1024 * 1024
  private static let maximumPDFPages = 200

  public static func importFile(at url: URL) throws -> [HistoricalMessage] {
    let fileExtension = url.pathExtension.lowercased()
    guard supportedExtensions.contains(fileExtension) else {
      throw HistoryImportError.invalid(
        "\(url.lastPathComponent) 的格式不支持。可导入 TXT、Markdown、JSON、JPG、PNG、Word 和 PDF。")
    }
    let didAccess = url.startAccessingSecurityScopedResource()
    defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    let limit = textExtensions.contains(fileExtension) ? textLimit : documentLimit
    guard size <= limit else {
      let readableLimit = limit / 1024 / 1024
      throw HistoryImportError.invalid(
        "\(url.lastPathComponent) 超过 \(readableLimit) MB，请压缩或拆分后导入。")
    }
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    let sourceID = "file:" + sha256(data)

    if textExtensions.contains(fileExtension) {
      return withProvenance(
        try HistoryImporter.parse(data: data, fileExtension: fileExtension), sourceID: sourceID)
    }
    if imageExtensions.contains(fileExtension) {
      return try imageRecords(data: data, sourceID: sourceID)
    }
    if fileExtension == "pdf" {
      return try pdfRecords(data: data, sourceID: sourceID)
    }
    if wordExtensions.contains(fileExtension) {
      let text = try extractWordText(from: url)
      return try extractedTextRecords(text, sourceID: sourceID)
    }
    throw HistoryImportError.invalid("无法读取这个文件。")
  }

  private static func withProvenance(
    _ records: [HistoricalMessage], sourceID: String
  ) -> [HistoricalMessage] {
    records.enumerated().map { index, record in
      var copy = record
      if copy.sourceID == nil { copy.sourceID = sourceID }
      if copy.sourceIndex == nil { copy.sourceIndex = index }
      return copy
    }
  }

  private static func extractedTextRecords(
    _ text: String, sourceID: String
  ) throws -> [HistoricalMessage] {
    let data = Data(text.utf8)
    guard data.count <= textLimit else {
      throw HistoryImportError.invalid("提取后的文字超过 10 MB，请拆分原文件后导入。")
    }
    return withProvenance(
      try HistoryImporter.parse(data: data, fileExtension: "txt"), sourceID: sourceID)
  }

  private static func imageRecords(data: Data, sourceID: String) throws -> [HistoricalMessage] {
    let lines = try recognizeText(in: data)
    guard !lines.isEmpty else {
      throw HistoryImportError.invalid("图片中没有识别到可导入的文字。")
    }
    return lines.enumerated().map { index, line in
      HistoricalMessage(
        speaker: speaker(for: line.boundingBox), kind: "image_ocr", text: line.text,
        sourceID: sourceID, sourceIndex: index)
    }
  }

  private static func pdfRecords(data: Data, sourceID: String) throws -> [HistoricalMessage] {
    guard let document = PDFDocument(data: data) else {
      throw HistoryImportError.invalid("PDF 无法读取，文件可能已损坏或加密。")
    }
    guard !document.isEncrypted || document.unlock(withPassword: "") else {
      throw HistoryImportError.invalid("PDF 受密码保护，请先解除密码后再导入。")
    }
    guard document.pageCount <= maximumPDFPages else {
      throw HistoryImportError.invalid("PDF 超过 \(maximumPDFPages) 页，请拆分后导入。")
    }

    var records: [HistoricalMessage] = []
    for pageIndex in 0..<document.pageCount {
      guard let page = document.page(at: pageIndex) else { continue }
      let pageSourceID = "\(sourceID):page:\(pageIndex + 1)"
      let extracted = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if extracted.count >= 8 {
        let pageRecords = try extractedTextRecords(extracted, sourceID: pageSourceID)
        records.append(contentsOf: pageRecords.map { record in
          var copy = record
          if copy.timestamp.isEmpty { copy.timestamp = "第 \(pageIndex + 1) 页" }
          return copy
        })
      } else {
        let lines = try recognizeText(in: renderedImageData(for: page))
        records.append(contentsOf: lines.enumerated().map { lineIndex, line in
          HistoricalMessage(
            timestamp: "第 \(pageIndex + 1) 页", speaker: speaker(for: line.boundingBox),
            kind: "pdf_ocr", text: line.text, sourceID: pageSourceID,
            sourceIndex: lineIndex)
        })
      }
    }
    guard !records.isEmpty else {
      throw HistoryImportError.invalid("PDF 中没有提取或识别到可导入的文字。")
    }
    return records
  }

  private static func extractWordText(from url: URL) throws -> String {
    let process = Process()
    let output = Pipe()
    let errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
    process.arguments = ["-convert", "txt", "-encoding", "UTF-8", "-stdout", url.path]
    process.standardOutput = output
    process.standardError = errors
    do { try process.run() }
    catch {
      throw HistoryImportError.invalid("无法启动本机 Word 文字提取器。")
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
      let text = String(data: data, encoding: .utf8),
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      let detail = String(
        data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw HistoryImportError.invalid(
        detail.isEmpty ? "Word 文件中没有提取到可导入的文字。" : "Word 文件无法读取：\(detail)")
    }
    return text
  }

  private struct RecognizedLine {
    var text: String
    var boundingBox: CGRect
  }

  private static func recognizeText(in data: Data) throws -> [RecognizedLine] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
    let handler = VNImageRequestHandler(data: data, options: [:])
    do { try handler.perform([request]) }
    catch { throw HistoryImportError.invalid("图片文字识别失败：\(error.localizedDescription)") }
    return (request.results ?? []).compactMap { observation in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
      return text.isEmpty ? nil : RecognizedLine(text: text, boundingBox: observation.boundingBox)
    }.sorted { lhs, rhs in
      if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.02 {
        return lhs.boundingBox.midY > rhs.boundingBox.midY
      }
      return lhs.boundingBox.minX < rhs.boundingBox.minX
    }
  }

  private static func speaker(for box: CGRect) -> String {
    if box.width > 0.78 { return "历史原文" }
    if box.midX < 0.43 { return "左侧" }
    if box.midX > 0.57 { return "右侧" }
    return "历史原文"
  }

  private static func renderedImageData(for page: PDFPage) throws -> Data {
    let bounds = page.bounds(for: .mediaBox)
    guard bounds.width > 0, bounds.height > 0 else {
      throw HistoryImportError.invalid("PDF 页面尺寸无效。")
    }
    let maximumDimension: CGFloat = 2400
    let scale = min(3, maximumDimension / max(bounds.width, bounds.height))
    let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
    let image = page.thumbnail(of: size, for: .mediaBox)
    guard let representation = NSBitmapImageRep(
      data: image.tiffRepresentation ?? Data()),
      let data = representation.representation(using: .png, properties: [:])
    else { throw HistoryImportError.invalid("PDF 扫描页无法转换为本机 OCR 图片。") }
    return data
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
