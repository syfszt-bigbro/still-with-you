import AppKit
import Foundation
import PDFKit
import StillWithYouCore
import StillWithYouImport

struct CheckError: Error, CustomStringConvertible {
  let description: String
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  if !condition() { throw CheckError(description: message) }
}

func fixtureImage() throws -> NSImage {
  let size = NSSize(width: 1800, height: 900)
  let image = NSImage(size: size)
  image.lockFocus()
  NSColor.white.setFill()
  NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
  let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 72, weight: .semibold),
    .foregroundColor: NSColor.black,
  ]
  NSString(string: "Alice hello there").draw(at: NSPoint(x: 80, y: 650), withAttributes: attributes)
  NSString(string: "Bob good morning").draw(at: NSPoint(x: 1120, y: 420), withAttributes: attributes)
  image.unlockFocus()
  return image
}

func writeJPEG(_ image: NSImage, to url: URL) throws {
  guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
    let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95])
  else { throw CheckError(description: "Could not encode JPEG fixture") }
  try jpeg.write(to: url)
}

func runTextutil(_ arguments: [String]) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
  process.arguments = arguments
  try process.run()
  process.waitUntilExit()
  try check(process.terminationStatus == 0, "textutil fixture conversion failed")
}

let root = FileManager.default.temporaryDirectory
  .appendingPathComponent("StillWithYouImportChecks-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let keepFixtures = ProcessInfo.processInfo.environment["STILL_WITH_YOU_KEEP_FIXTURES"] == "1"
defer { if !keepFixtures { try? FileManager.default.removeItem(at: root) } }

let image = try fixtureImage()
let jpegURL = root.appendingPathComponent("chat.jpg")
try writeJPEG(image, to: jpegURL)
let imageRecords = try HistoryDocumentImporter.importFile(at: jpegURL)
try check(imageRecords.contains { $0.speaker == "左侧" }, "JPG OCR did not preserve left side")
try check(imageRecords.contains { $0.speaker == "右侧" }, "JPG OCR did not preserve right side")
try check(imageRecords.map(\.text).joined(separator: " ").lowercased().contains("alice"), "JPG OCR lost text")
try check(
  HistoryImporter.merging(imageRecords, into: imageRecords).count == imageRecords.count,
  "Repeated JPG import created duplicates")

let pdfURL = root.appendingPathComponent("scan.pdf")
let document = PDFDocument()
guard let page = PDFPage(image: image) else { throw CheckError(description: "Could not make PDF page") }
document.insert(page, at: 0)
try check(document.write(to: pdfURL), "Could not write PDF fixture")
let pdfRecords = try HistoryDocumentImporter.importFile(at: pdfURL)
try check(pdfRecords.contains { $0.kind == "pdf_ocr" }, "Scanned PDF did not use OCR")
try check(pdfRecords.map(\.text).joined(separator: " ").lowercased().contains("morning"), "PDF OCR lost text")

let wordSource = root.appendingPathComponent("word-source.txt")
try "Alice: hello from Word\nBob: reply from document".write(
  to: wordSource, atomically: true, encoding: .utf8)
var wordRecordCount = 0
for wordExtension in ["doc", "docx", "rtf"] {
  let wordURL = root.appendingPathComponent("chat.\(wordExtension)")
  try runTextutil(["-convert", wordExtension, "-output", wordURL.path, wordSource.path])
  let wordRecords = try HistoryDocumentImporter.importFile(at: wordURL)
  try check(
    Set(wordRecords.map(\.speaker)) == Set(["Alice", "Bob"]),
    "\(wordExtension.uppercased()) speakers were not extracted")
  try check(
    wordRecords.allSatisfy { $0.sourceID != nil && $0.sourceIndex != nil },
    "\(wordExtension.uppercased()) provenance missing")
  wordRecordCount += wordRecords.count
}

print("History document import checks passed: JPG \(imageRecords.count), PDF \(pdfRecords.count), Word \(wordRecordCount)")
if keepFixtures { print("Fixture directory: \(root.path)") }
