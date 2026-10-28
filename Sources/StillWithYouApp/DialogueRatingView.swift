import SwiftUI
import StillWithYouCore

struct DialogueRating: ViewModifier {
  @ObservedObject var model: AppModel
  let message: ChatMessage
  @State private var hovering = false
  @State private var hideButtons: Task<Void, Never>?
  func body(content: Content) -> some View {
    content
      .padding(.bottom, message.role == "assistant" ? 24 : 0)
      .overlay(alignment: .bottomTrailing) {
        if message.role == "assistant" {
          HStack(spacing: 4) {
            voteButton(1, icon: "hand.thumbsup", label: "点赞：类似场景多用")
            voteButton(-1, icon: "hand.thumbsdown", label: "点踩：类似场景少用")
            Button { model.replayDialogue(message) } label: {
              Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 11)).frame(width: 23, height: 20)
                .foregroundStyle(Color.secondary)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
            }.buttonStyle(.plain).help("重新听").accessibilityLabel("重新听")

          }.padding(.trailing, 8).padding(.bottom, 3)
            .contentShape(Rectangle())
            .onHover { setHovering($0) }
            .opacity(hovering || model.dialogueVote(for: message) != nil ? 1 : 0)
            .allowsHitTesting(hovering || model.dialogueVote(for: message) != nil)
            .accessibilityHidden(false)
        }
      }
      .onHover { setHovering($0) }
  }
  private func setHovering(_ value: Bool) {
    hideButtons?.cancel()
    if value {
      hovering = true
    } else {
      // The pointer briefly leaves the bubble while crossing the gap to its
      // controls. Keep them alive long enough to receive the next hover event.
      hideButtons = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard !Task.isCancelled else { return }
        hovering = false
      }
    }
  }
  private func voteButton(_ value: Int, icon: String, label: String) -> some View {
    let selected = model.dialogueVote(for: message) == value
    return Button { model.rateDialogue(message, value: value) } label: {
      Image(systemName: icon + (selected ? ".fill" : ""))
        .font(.system(size: 11)).frame(width: 23, height: 20)
        .foregroundStyle(selected ? Color.lake : Color.secondary)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
    }.buttonStyle(.plain)
      .help(UIStrings.text(selected ? "再次点击取消" : label))
      .accessibilityLabel(UIStrings.text(label))
      .accessibilityValue(UIStrings.text(selected ? "已选择" : "未选择"))
  }
}
