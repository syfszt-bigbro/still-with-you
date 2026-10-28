import Foundation
import SwiftUI

/// Compatibility shim for older backups. Public builds intentionally do not
/// ship any private cloned-voice identifiers or third-party voice credentials.
@MainActor final class ClonedSpeech: ObservableObject {
  nonisolated static let defaultVoice = ""
  nonisolated static let maleVoice = ""
  nonisolated static let femaleVoice = ""
  @Published var status = "未配置云端语音；当前使用 macOS 系统朗读"
  @Published var busy = false
  var isPlaying = false
  var isSpeakingOrPreparing: Bool { busy || isPlaying }
  func stop() { busy = false; isPlaying = false }
  func speak(_ text: String, voice: String = "", onReady: (() -> Void)? = nil) { onReady?() }
}

struct ClonedSpeechSettings: View {
  @ObservedObject var model: AppModel
  @ObservedObject var voice: ClonedSpeech
  var body: some View {
    Card {
      Text("语音播报（可选）").font(.headline)
      Toggle("启用 macOS 系统朗读", isOn: Binding(
        get: { model.state.preferences.speechEnabled ?? true },
        set: { model.state.preferences.speechEnabled = $0; model.stopSpeaking(); model.save() }))
      Toggle("朗读聊天回复", isOn: Binding(
        get: { model.state.preferences.spokenChatReplies ?? false },
        set: { model.state.preferences.spokenChatReplies = $0; if !$0 { model.stopSpeaking() }; model.save() }))
      Text("无需 API Key。系统会使用这台 Mac 已安装的声音；不启用也不影响文字聊天、计划、提醒和备份。")
        .font(.caption).foregroundStyle(.secondary)
    }
  }
}
