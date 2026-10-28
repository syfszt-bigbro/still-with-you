import AppKit
import SwiftUI

final class ClickableChatField: NSTextField {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
    super.mouseDown(with: event)
  }
}

/// Native editor keeps Chinese composition and SwiftUI's draft synchronized.
struct ChatInput: NSViewRepresentable {
  @Binding var text: String
  var placeholder: String
  var focusRequest: UUID? = nil
  var submit: () -> Void
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSTextField {
    let field = ClickableChatField(string: text)
    field.placeholderString = placeholder
    field.isBordered = false; field.drawsBackground = false
    field.font = .systemFont(ofSize: 14)
    field.focusRingType = .none
    field.isContinuous = false
    field.delegate = context.coordinator
    return field
  }
  func updateNSView(_ field: NSTextField, context: Context) {
    context.coordinator.parent = self
    field.placeholderString = placeholder
    if let focusRequest, context.coordinator.lastFocusRequest != focusRequest {
      context.coordinator.lastFocusRequest = focusRequest
      DispatchQueue.main.async { [weak field] in
        guard let field, let window = field.window, window.isKeyWindow else { return }
        window.makeFirstResponder(field)
      }
    }
    // Never overwrite an active IME composition with an older SwiftUI value.
    if field.currentEditor() == nil && field.stringValue != text { field.stringValue = text }
    if text.isEmpty && !context.coordinator.lastText.isEmpty {
      let coordinator = context.coordinator
      DispatchQueue.main.async { [weak field] in
        // A queued SwiftUI render may carry the previous empty draft while
        // AppKit is composing text. Re-read the binding before clearing.
        guard coordinator.parent.text.isEmpty, let field else { return }
        field.stringValue = ""
        field.currentEditor()?.string = ""
        coordinator.lastText = ""
      }
    }
  }
  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: ChatInput
    var lastText = ""
    var lastFocusRequest: UUID?
    init(_ parent: ChatInput) { self.parent = parent }
    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      lastText = field.stringValue
      parent.text = field.stringValue
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      guard commandSelector == #selector(NSResponder.insertNewline(_:)), !textView.hasMarkedText(),
        let field = control as? NSTextField else { return false }
      send(field)
      return true
    }
    func send(_ field: NSTextField) {
      parent.text = field.stringValue
      parent.submit()
      field.stringValue = parent.text
      lastText = parent.text
    }
  }
}
