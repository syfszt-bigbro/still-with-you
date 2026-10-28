import Foundation
import StillWithYouCore

@main struct SpeechExclusionCheck {
  @MainActor static func main() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("speech-check-\(UUID())")
    setenv("STILL_WITH_YOU_DATA_DIR", folder.path, 1)
    defer { try? FileManager.default.removeItem(at: folder) }
    let model = AppModel()
    model.state.preferences.aiEnabled = false
    model.state.preferences.speechEnabled = true
    model.state.preferences.clonedSpeechEnabled = true
    model.state.preferences.spokenChatReplies = true
    model.state.timer = nil
    model.reviewID = nil
    model.chatDraft = ""
    precondition(model.canAcceptPetReaction)
    // Simulate an in-flight voice request without contacting the paid service.
    model.clonedSpeech.busy = true
    model.preparingSpeech = true
    let count = model.state.messages.count
    model.replayDialogue(ChatMessage(role: "assistant", content: "不得抢话"))
    precondition((model.state.dialogueReplays ?? []).isEmpty)
    model.reactToPet(.dizzy)
    precondition(model.state.messages.count == count)
    model.speak("不得抢话")
    precondition(model.clonedSpeech.busy)
    model.publishSpokenReply(ChatMessage(role: "assistant", content: "文字仍然可见"))
    precondition(model.state.messages.count == count + 1)
    precondition(model.preparingSpeech && model.clonedSpeech.busy)
    var revealed = false
    model.clonedSpeech.speak("不得替换", onReady: { revealed = true })
    precondition(revealed && model.clonedSpeech.busy)
    model.preparingSpeech = false
    model.clonedSpeech.busy = false
    model.reviewID = UUID()
    precondition(!model.canAcceptPetReaction)
    model.reviewID = nil
    var timer = FocusTimer(taskID: UUID(), phase: .focus, duration: 60)
    timer.awaitingReflection = true
    model.state.timer = timer
    precondition(!model.canAcceptPetReaction)
    model.state.timer = nil
    model.chatDraft = "正在填写"
    precondition(!model.canAcceptPetReaction)
    model.chatDraft = ""
    precondition(model.canAcceptPetReaction)
    let line = ChatMessage(role: "assistant", content: "歇一哈嘛")
    model.state.messages.append(line)
    model.rememberReplay(line); model.rememberReplay(line)
    precondition(model.state.dialogueReplays?.first?.replayCount == 2)
    precondition(model.dialogueVote(for: line) == nil)
    model.rateDialogue(line, value: -1)
    precondition(model.effectiveDialogueVotes.filter { $0.messageID == line.id }.count == 1)
    precondition(model.effectiveDialogueVotes.first { $0.messageID == line.id }?.value == -1)
    model.state.preferences.automaticLearning = false
    model.rememberReplay(line)
    precondition(model.state.dialogueReplays?.first?.replayCount == 2)
    print("PASS: speech exclusion, text delivery, reflection and input interaction locks")
  }
}
