import AppKit
import Foundation

public struct CharacterFraming: Codable, Equatable, Sendable {
  public var zoom: Double
  public var horizontal: Double
  public var vertical: Double

  public init(zoom: Double = 1, horizontal: Double = 0, vertical: Double = 0) {
    self.zoom = zoom
    self.horizontal = horizontal
    self.vertical = vertical
  }

  public var clamped: CharacterFraming {
    CharacterFraming(
      zoom: min(3, max(1, zoom)),
      horizontal: min(1, max(-1, horizontal)),
      vertical: min(1, max(-1, vertical)))
  }
}

public struct CharacterAssetManifest: Codable {
  public var formatVersion = 2
  public var createdAt = Date()
  public var actions: [String]
  public var spriteSheet: String
  public var avatar: String
  public var sourceImage: String?
  public var framing: CharacterFraming?

  public init(
    actions: [String], spriteSheet: String, avatar: String,
    sourceImage: String? = nil, framing: CharacterFraming? = nil
  ) {
    self.actions = actions
    self.spriteSheet = spriteSheet
    self.avatar = avatar
    self.sourceImage = sourceImage
    self.framing = framing
  }
}

public struct CharacterAssetError: LocalizedError {
  public var message: String
  public var errorDescription: String? { message }
  public init(message: String) { self.message = message }
}

public enum CharacterAssetBuilder {
  public static let actions = [
    "idle", "run-right", "run-left", "wave", "jump", "encourage",
    "wait", "think", "review", "look-a", "look-b",
  ]

  public static func build(
    from sourceURL: URL, framing: CharacterFraming = CharacterFraming(), in root: URL
  ) throws -> CharacterAssetManifest {
    guard let source = NSImage(contentsOf: sourceURL), source.size.width > 0, source.size.height > 0 else {
      throw CharacterAssetError(message: "无法读取这张图片，请选择 PNG、JPEG、HEIC 或 WebP。")
    }
    return try build(from: source, framing: framing, in: root)
  }

  public static func build(
    from source: NSImage, framing: CharacterFraming = CharacterFraming(), in root: URL
  ) throws -> CharacterAssetManifest {
    guard source.size.width > 0, source.size.height > 0 else {
      throw CharacterAssetError(message: "这张图片没有可用的画面尺寸。")
    }
    let framing = framing.clamped
    let framedSource = framedImage(source, framing: framing, size: 1024)
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
        draw(source: framedSource, in: cell, row: row, column: column)
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
    drawAspectFit(framedSource, in: NSRect(x: 34, y: 34, width: 444, height: 444), radius: 72)
    avatar.unlockFocus()
    let avatarURL = folder.appendingPathComponent("custom-avatar.png")
    try pngData(avatar).write(to: avatarURL, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: avatarURL.path)

    for (row, action) in actions.enumerated() {
      // Render standalone previews directly. Cropping an AppKit canvas through
      // CGImage mixes bottom-left and top-left coordinate systems and used to
      // export an unrelated corner of the sprite sheet.
      let image = NSImage(size: NSSize(width: 192, height: 208))
      image.lockFocus()
      NSColor.clear.setFill()
      NSRect(x: 0, y: 0, width: 192, height: 208).fill()
      draw(source: framedSource, in: NSRect(x: 0, y: 0, width: 192, height: 208), row: row, column: 0)
      image.unlockFocus()
      let url = actionFolder.appendingPathComponent(action + ".png")
      try pngData(image).write(to: url, options: .atomic)
      try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    let sourceURL = folder.appendingPathComponent("source-private.png")
    try pngData(source).write(to: sourceURL, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sourceURL.path)

    let manifest = CharacterAssetManifest(
      actions: actions, spriteSheet: sheetURL.lastPathComponent, avatar: avatarURL.lastPathComponent,
      sourceImage: sourceURL.lastPathComponent, framing: framing)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let manifestURL = folder.appendingPathComponent("manifest.json")
    try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
    return manifest
  }

  public static func framedPreview(
    from source: NSImage, framing: CharacterFraming, size: CGFloat = 420
  ) -> NSImage {
    framedImage(source, framing: framing.clamped, size: size)
  }

  public static func actionPreview(
    from source: NSImage, framing: CharacterFraming, actionIndex: Int = 0
  ) -> NSImage {
    let framedSource = framedImage(source, framing: framing.clamped, size: 1024)
    let row = min(actions.count - 1, max(0, actionIndex))
    let image = NSImage(size: NSSize(width: 192, height: 208))
    image.lockFocus()
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 192, height: 208).fill()
    draw(source: framedSource, in: NSRect(x: 0, y: 0, width: 192, height: 208), row: row, column: 0)
    image.unlockFocus()
    return image
  }

  private static func framedImage(
    _ source: NSImage, framing: CharacterFraming, size: CGFloat
  ) -> NSImage {
    let output = NSImage(size: NSSize(width: size, height: size))
    output.lockFocus()
    NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.96, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let baseScale = min(size / source.size.width, size / source.size.height)
    let scale = baseScale * CGFloat(framing.zoom)
    let drawSize = NSSize(width: source.size.width * scale, height: source.size.height * scale)
    let overflowX = max(0, (drawSize.width - size) / 2)
    let overflowY = max(0, (drawSize.height - size) / 2)
    let origin = NSPoint(
      x: (size - drawSize.width) / 2 - overflowX * CGFloat(framing.horizontal),
      y: (size - drawSize.height) / 2 + overflowY * CGFloat(framing.vertical))
    source.draw(
      in: NSRect(origin: origin, size: drawSize), from: .zero,
      operation: .sourceOver, fraction: 1)
    output.unlockFocus()
    return output
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
    drawAspectFit(source, in: cell.insetBy(dx: 18, dy: 14), radius: 26)
    let symbols = [
      "sparkles", "arrow.right", "arrow.left", "hand.wave.fill", "arrow.up",
      "heart.fill", "hourglass", "lightbulb.fill", "checkmark.circle.fill", "eye.fill", "eyes",
    ]
    if symbols.indices.contains(row),
      let symbol = NSImage(systemSymbolName: symbols[row], accessibilityDescription: nil)
    {
      let badge = NSRect(x: cell.maxX - 54, y: cell.maxY - 54, width: 36, height: 36)
      NSColor(calibratedWhite: 0.12, alpha: 0.82).setFill()
      NSBezierPath(ovalIn: badge).fill()
      let whiteSymbol = symbol.withSymbolConfiguration(
        NSImage.SymbolConfiguration(paletteColors: [.white])) ?? symbol
      whiteSymbol.draw(in: badge.insetBy(dx: 8, dy: 8), from: .zero, operation: .sourceOver, fraction: 1)
    }
    NSGraphicsContext.restoreGraphicsState()
  }

  private static func drawAspectFit(_ image: NSImage, in rect: NSRect, radius: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
    NSColor(calibratedRed: 0.94, green: 0.95, blue: 0.96, alpha: 0.98).setFill()
    rect.fill()
    let sourceAspect = image.size.width / image.size.height
    let targetAspect = rect.width / rect.height
    var drawRect = rect
    if sourceAspect > targetAspect {
      drawRect.size.height = rect.width / sourceAspect
      drawRect.origin.y = rect.midY - drawRect.height / 2
    } else {
      drawRect.size.width = rect.height * sourceAspect
      drawRect.origin.x = rect.midX - drawRect.width / 2
    }
    image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    NSColor(calibratedWhite: 0.25, alpha: 0.24).setStroke()
    let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
    border.lineWidth = 1
    border.stroke()
  }

  private static func pngData(_ image: NSImage) throws -> Data {
    let width = max(1, Int(image.size.width.rounded()))
    let height = max(1, Int(image.size.height.rounded()))
    guard let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
      throw CharacterAssetError(message: "无法写出 PNG 动作图。")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    image.draw(
      in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero,
      operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
      throw CharacterAssetError(message: "无法写出 PNG 动作图。")
    }
    return data
  }
}
