import AppKit
import Foundation

struct CharacterAssetManifest: Codable {
  var formatVersion = 1
  var createdAt = Date()
  var actions: [String]
  var spriteSheet: String
  var avatar: String
}

enum CharacterAssetBuilder {
  static let actions = [
    "idle", "run-right", "run-left", "wave", "jump", "encourage",
    "wait", "think", "review", "look-a", "look-b",
  ]

  static func build(from sourceURL: URL, in root: URL) throws -> CharacterAssetManifest {
    guard let source = NSImage(contentsOf: sourceURL), source.size.width > 0, source.size.height > 0 else {
      throw AppFailure(message: "无法读取这张图片，请选择 PNG、JPEG、HEIC 或 WebP。")
    }
    let fm = FileManager.default
    let folder = root.appendingPathComponent("character", isDirectory: true)
    let actionFolder = folder.appendingPathComponent("actions", isDirectory: true)
    try fm.createDirectory(at: actionFolder, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])

    let sheet = NSImage(size: NSSize(width: 1536, height: 2288))
    sheet.lockFocus()
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 1536, height: 2288).fill()
    for row in 0..<11 {
      for column in 0..<8 {
        let cell = NSRect(x: column * 192, y: (10 - row) * 208, width: 192, height: 208)
        draw(source: source, in: cell, row: row, column: column)
      }
    }
    sheet.unlockFocus()

    let sheetURL = folder.appendingPathComponent("custom-spritesheet.png")
    try pngData(sheet).write(to: sheetURL, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sheetURL.path)

    let avatar = NSImage(size: NSSize(width: 512, height: 512))
    avatar.lockFocus()
    NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.94, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 512, height: 512), xRadius: 112, yRadius: 112).fill()
    drawAspectFill(source, in: NSRect(x: 34, y: 34, width: 444, height: 444), radius: 104)
    avatar.unlockFocus()
    let avatarURL = folder.appendingPathComponent("custom-avatar.png")
    try pngData(avatar).write(to: avatarURL, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: avatarURL.path)

    guard let cg = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      throw AppFailure(message: "动作图生成失败。")
    }
    for (row, action) in actions.enumerated() {
      guard let crop = cg.cropping(to: CGRect(x: 0, y: (10 - row) * 208, width: 192, height: 208)) else { continue }
      let image = NSImage(cgImage: crop, size: NSSize(width: 192, height: 208))
      let url = actionFolder.appendingPathComponent(action + ".png")
      try pngData(image).write(to: url, options: .atomic)
      try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    let manifest = CharacterAssetManifest(
      actions: actions, spriteSheet: sheetURL.lastPathComponent, avatar: avatarURL.lastPathComponent)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let manifestURL = folder.appendingPathComponent("manifest.json")
    try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
    return manifest
  }

  private static func draw(source: NSImage, in cell: NSRect, row: Int, column: Int) {
    let progress = Double(column) / 7.0
    let dx: CGFloat
    let dy: CGFloat
    let angle: CGFloat
    switch row {
    case 1: dx = CGFloat(progress) * 12 - 6; dy = CGFloat(sin(progress * .pi * 2)) * 3; angle = -2
    case 2: dx = 6 - CGFloat(progress) * 12; dy = CGFloat(sin(progress * .pi * 2)) * 3; angle = 2
    case 3: dx = 0; dy = 0; angle = CGFloat(sin(progress * .pi * 2) * 4)
    case 4: dx = 0; dy = CGFloat(sin(progress * .pi)) * 16; angle = 0
    case 5: dx = 0; dy = 0; angle = CGFloat(sin(progress * .pi * 2) * 2)
    case 6: dx = 0; dy = CGFloat(sin(progress * .pi * 2) * 2); angle = 0
    case 7: dx = 0; dy = 0; angle = -3
    case 8: dx = 0; dy = 0; angle = 3
    case 9, 10: dx = CGFloat(column - 3) * 1.5; dy = 0; angle = CGFloat(column - 3) * 0.7
    default: dx = 0; dy = CGFloat(sin(progress * .pi * 2) * 2); angle = 0
    }
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: cell.midX + dx, yBy: cell.midY + dy)
    transform.rotate(byDegrees: angle)
    transform.translateX(by: -cell.midX, yBy: -cell.midY)
    transform.concat()
    NSColor(calibratedRed: 0.36, green: 0.49, blue: 0.65, alpha: 0.14).setFill()
    NSBezierPath(ovalIn: cell.insetBy(dx: 18, dy: 12)).fill()
    drawAspectFill(source, in: cell.insetBy(dx: 22, dy: 15), radius: 72)
    if row == 3, let symbol = NSImage(systemSymbolName: "hand.wave.fill", accessibilityDescription: nil) {
      symbol.draw(in: NSRect(x: cell.maxX - 52, y: cell.maxY - 58, width: 34, height: 34))
    }
    NSGraphicsContext.restoreGraphicsState()
  }

  private static func drawAspectFill(_ image: NSImage, in rect: NSRect, radius: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    let sourceAspect = image.size.width / image.size.height
    let targetAspect = rect.width / rect.height
    var drawRect = rect
    if sourceAspect > targetAspect {
      drawRect.size.width = rect.height * sourceAspect
      drawRect.origin.x = rect.midX - drawRect.width / 2
    } else {
      drawRect.size.height = rect.width / sourceAspect
      drawRect.origin.y = rect.midY - drawRect.height / 2
    }
    image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
  }

  private static func pngData(_ image: NSImage) throws -> Data {
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let data = bitmap.representation(using: .png, properties: [:]) else {
      throw AppFailure(message: "无法写出 PNG 动作图。")
    }
    return data
  }
}
