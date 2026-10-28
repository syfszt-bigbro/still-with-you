import AppKit
import Foundation

let output = CommandLine.arguments.dropFirst().first.map(URL.init(fileURLWithPath:))
  ?? URL(fileURLWithPath: "Sources/StillWithYouApp/Resources/default-spritesheet.png")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

let sheet = NSImage(size: NSSize(width: 1536, height: 2288))
sheet.lockFocus()
NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: 1536, height: 2288).fill()
for row in 0..<11 {
  for column in 0..<8 {
    let progress = Double(column) / 7.0
    let cell = NSRect(x: column * 192, y: (10 - row) * 208, width: 192, height: 208)
    let bounce = CGFloat(sin(progress * .pi * 2)) * (row == 4 ? 14 : 3)
    let lean: CGFloat = row == 1 ? -5 : row == 2 ? 5 : row == 7 ? -3 : row == 8 ? 3 : 0
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: cell.midX, yBy: cell.midY + bounce)
    transform.rotate(byDegrees: lean + (row >= 9 ? CGFloat(column - 3) : 0))
    transform.translateX(by: -cell.midX, yBy: -cell.midY)
    transform.concat()

    let shadow = NSBezierPath(ovalIn: NSRect(x: cell.midX - 55, y: cell.minY + 13, width: 110, height: 17))
    NSColor(calibratedWhite: 0.1, alpha: 0.10).setFill(); shadow.fill()
    let body = NSBezierPath(roundedRect: NSRect(x: cell.midX - 48, y: cell.minY + 38, width: 96, height: 105), xRadius: 35, yRadius: 35)
    NSColor(calibratedRed: 0.36, green: 0.49, blue: 0.65, alpha: 1).setFill(); body.fill()
    let head = NSBezierPath(ovalIn: NSRect(x: cell.midX - 43, y: cell.minY + 121, width: 86, height: 75))
    NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.22, alpha: 1).setFill(); head.fill()
    let trace = NSBezierPath()
    trace.lineWidth = 5; trace.lineCapStyle = .round
    trace.move(to: NSPoint(x: cell.midX - 62, y: cell.minY + 92))
    trace.curve(to: NSPoint(x: cell.midX + 67, y: cell.minY + 85),
      controlPoint1: NSPoint(x: cell.midX - 15, y: cell.minY + 117),
      controlPoint2: NSPoint(x: cell.midX + 26, y: cell.minY + 59))
    NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.47, alpha: 0.95).setStroke(); trace.stroke()
    if row == 3 {
      let arm = NSBezierPath(); arm.lineWidth = 14; arm.lineCapStyle = .round
      arm.move(to: NSPoint(x: cell.midX + 36, y: cell.minY + 123))
      arm.line(to: NSPoint(x: cell.midX + 63, y: cell.minY + 155 + CGFloat(column % 2) * 12))
      NSColor(calibratedRed: 0.36, green: 0.49, blue: 0.65, alpha: 1).setStroke(); arm.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
  }
}
sheet.unlockFocus()
guard let tiff = sheet.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
  let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
try data.write(to: output, options: .atomic)

let iconURL = output.deletingLastPathComponent().appendingPathComponent("AppIcon.png")
let icon = NSImage(size: NSSize(width: 1024, height: 1024))
icon.lockFocus()
NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.94, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 976, height: 976), xRadius: 220, yRadius: 220).fill()
NSColor(calibratedRed: 0.15, green: 0.16, blue: 0.22, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 342, y: 520, width: 340, height: 340)).fill()
NSColor(calibratedRed: 0.36, green: 0.49, blue: 0.65, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 310, y: 210, width: 404, height: 390), xRadius: 145, yRadius: 145).fill()
let iconTrace = NSBezierPath(); iconTrace.lineWidth = 30; iconTrace.lineCapStyle = .round
iconTrace.move(to: NSPoint(x: 190, y: 425))
iconTrace.curve(to: NSPoint(x: 840, y: 392), controlPoint1: NSPoint(x: 360, y: 565), controlPoint2: NSPoint(x: 646, y: 242))
NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.47, alpha: 1).setStroke(); iconTrace.stroke()
icon.unlockFocus()
guard let iconTiff = icon.tiffRepresentation, let iconBitmap = NSBitmapImageRep(data: iconTiff),
  let iconData = iconBitmap.representation(using: .png, properties: [:]) else { fatalError("Icon encoding failed") }
try iconData.write(to: iconURL, options: .atomic)
print(output.path)
