import Foundation
import AppKit
import StillWithYouCore
@main struct RatingCheck {
 @MainActor static func main() throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rating-\(UUID())")
  setenv("STILL_WITH_YOU_DATA_DIR", folder.path, 1)
  defer { try? FileManager.default.removeItem(at: folder) }
  let model = AppModel()
  model.state.preferences.aiEnabled = false
  model.state.preferences.spokenTaskReplies = false
  let sprite = SpriteView(model: model)
  // Reproduce the exact crash: reach row remains after reachStarted is cleared.
  for row in [11, 9, 10, -1, 99] {
    sprite.row = row
    sprite.advanceFrame()
    precondition(sprite.row == 0 && sprite.col == 0)
  }
  for _ in 0..<1000 {
    sprite.row = 11; sprite.currentState = "reach"
    let event = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    sprite.mouseDown(with: event)
    precondition(sprite.currentState == "idle" && sprite.row == 0)
    sprite.updateAnimation()
    sprite.mouseUp(with: event)
  }
  print("PASS: interrupted reach frame bounds and 1000 click/animation/release cycles")
 }
}
