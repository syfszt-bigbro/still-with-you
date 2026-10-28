import AppKit
import SwiftUI

/// Keep AppKit's date field editor stable while the application's timer publishes ticks.
struct RecordDateInput: NSViewRepresentable {
  @Binding var value: Date
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSDatePicker {
    let picker = NSDatePicker()
    picker.datePickerStyle = .textFieldAndStepper
    picker.datePickerElements = [.yearMonthDay, .hourMinuteSecond]
    picker.datePickerMode = .single
    picker.isBezeled = true
    picker.drawsBackground = true
    picker.dateValue = value
    picker.target = context.coordinator
    picker.action = #selector(Coordinator.changed(_:))
    return picker
  }
  func updateNSView(_ picker: NSDatePicker, context: Context) {
    context.coordinator.parent = self
    // Do not reset a partially typed date on unrelated model updates.
    if abs(picker.dateValue.timeIntervalSince(value)) > 0.001 {
      picker.dateValue = value
    }
  }
  final class Coordinator: NSObject {
    var parent: RecordDateInput
    init(_ parent: RecordDateInput) { self.parent = parent }
    @objc func changed(_ picker: NSDatePicker) { parent.value = picker.dateValue }
  }
}
