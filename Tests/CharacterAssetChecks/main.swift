import AppKit
import Foundation
import StillWithYouAssets

func pngData(_ image: NSImage) throws -> Data {
  guard let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let data = bitmap.representation(using: .png, properties: [:])
  else { throw CharacterAssetError(message: "test image encoding failed") }
  return data
}

func containsFourSourceBands(_ url: URL) -> Bool {
  guard let image = NSImage(contentsOf: url),
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff)
  else { return false }
  var found = Set<String>()
  for y in stride(from: 4, to: bitmap.pixelsHigh - 4, by: 4) {
    for x in stride(from: 4, to: bitmap.pixelsWide - 4, by: 4) {
      guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
        color.alphaComponent > 0.7 else { continue }
      let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
      // Display-P3 images converted by AppKit can give pure green a red
      // component around 0.5. Detect dominant bands instead of assuming sRGB.
      if r > 0.75, r > g + 0.45, r > b + 0.45 { found.insert("red") }
      if g > 0.65, g > r + 0.25, g > b + 0.25 { found.insert("green") }
      if b > 0.7, b > r + 0.35, b > g + 0.35 { found.insert("blue") }
      if r > 0.75, g > 0.65, b < min(r, g) - 0.35 { found.insert("yellow") }
    }
  }
  return found.count == 4
}

let keepPreview = ProcessInfo.processInfo.environment["KEEP_CHARACTER_ASSET_PREVIEW"] == "1"
let root = FileManager.default.temporaryDirectory.appendingPathComponent(
  keepPreview ? "still-with-you-character-preview" : "character-assets-\(UUID().uuidString)",
  isDirectory: true)
if keepPreview { try? FileManager.default.removeItem(at: root) }
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { if !keepPreview { try? FileManager.default.removeItem(at: root) } }

// A deliberately wide source detects accidental aspect-fill cropping: all four
// bands must remain visible in both the avatar and every representative action.
let source = NSImage(size: NSSize(width: 400, height: 100))
source.lockFocus()
for (index, color) in [NSColor.red, .green, .blue, .yellow].enumerated() {
  color.setFill()
  NSRect(x: index * 100, y: 0, width: 100, height: 100).fill()
}
source.unlockFocus()
let sourceURL = root.appendingPathComponent("source.png")
try pngData(source).write(to: sourceURL)

let manifest = try CharacterAssetBuilder.build(from: sourceURL, in: root)
precondition(manifest.actions.count == 11)
precondition(manifest.formatVersion == 2)
precondition(manifest.sourceImage == "source-private.png")
precondition(manifest.framing == CharacterFraming())
let character = root.appendingPathComponent("character", isDirectory: true)
let sheetURL = character.appendingPathComponent(manifest.spriteSheet)
let avatarURL = character.appendingPathComponent(manifest.avatar)
let privateSourceURL = character.appendingPathComponent("source-private.png")
precondition(FileManager.default.fileExists(atPath: sheetURL.path))
precondition(FileManager.default.fileExists(atPath: privateSourceURL.path))
precondition(containsFourSourceBands(avatarURL), "avatar cropped away part of the uploaded photo")
for action in manifest.actions {
  let actionURL = character.appendingPathComponent("actions/\(action).png")
  precondition(FileManager.default.fileExists(atPath: actionURL.path))
  precondition(containsFourSourceBands(actionURL), "\(action) cropped away part of the uploaded photo")
}

let originalAvatar = try Data(contentsOf: avatarURL)
let adjusted = CharacterFraming(zoom: 2.2, horizontal: 0.7, vertical: -0.4)
let adjustedManifest = try CharacterAssetBuilder.build(
  from: sourceURL, framing: adjusted, in: root)
precondition(adjustedManifest.framing == adjusted)
let adjustedAvatar = try Data(contentsOf: avatarURL)
precondition(adjustedAvatar != originalAvatar,
  "changing the framing did not change the generated avatar")
let decoded = try JSONDecoder().decode(
  CharacterAssetManifest.self,
  from: Data(contentsOf: character.appendingPathComponent("manifest.json")))
precondition(decoded.framing == adjusted)
precondition(decoded.sourceImage == "source-private.png")

let clamped = CharacterFraming(zoom: 9, horizontal: -8, vertical: 4).clamped
precondition(clamped == CharacterFraming(zoom: 3, horizontal: -1, vertical: 1))
let framedPreview = CharacterAssetBuilder.framedPreview(
  from: source, framing: CharacterFraming(), size: 320)
precondition(framedPreview.size == NSSize(width: 320, height: 320))
let actionPreview = CharacterAssetBuilder.actionPreview(
  from: source, framing: adjusted, actionIndex: 3)
precondition(actionPreview.size == NSSize(width: 192, height: 208))

print("PASS: photo preview, adjustable framing, private source and 11 generated actions")
if keepPreview { print("PREVIEW: \(root.path)") }
