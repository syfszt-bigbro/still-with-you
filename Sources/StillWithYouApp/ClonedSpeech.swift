import AVFoundation
import Foundation
import Security
import StillWithYouCore
import SwiftUI

/// Optional BYOK cloud speech. The public app ships no private voice identifier
/// or credential; both the API key and voice ID belong to the person using it.
@MainActor final class ClonedSpeech: NSObject, ObservableObject, AVAudioPlayerDelegate {
  @Published var status = "当前使用 macOS 系统朗读；也可配置百炼复刻音色。"
  @Published var busy = false
  private var player: AVAudioPlayer?
  private var work: Task<Void, Never>?
  private var generation = UUID()
  private var cachedKey: String?
  private var ready: (() -> Void)?
  private var failed: ((String) -> Void)?
  private var deadline: Task<Void, Never>?

  var isPlaying: Bool { player?.isPlaying == true }
  var isSpeakingOrPreparing: Bool { busy || isPlaying }

  func saveKey(_ value: String) async -> Bool {
    let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return false }
    let result = await Task.detached {
      CredentialVault.call("write", account: "cosyvoice", value: key)
    }.value
    if result.status == errSecSuccess {
      cachedKey = key
      status = "百炼语音密钥已保存到本机钥匙串。"
      return true
    }
    status = "语音密钥保存失败（\(result.status)），请重试。"
    return false
  }

  func deleteKey() async -> Bool {
    let result = await Task.detached {
      CredentialVault.call("delete", account: "cosyvoice")
    }.value
    if result.status == errSecSuccess || result.status == errSecItemNotFound {
      cachedKey = nil
      status = "已从本机钥匙串删除百炼语音密钥。"
      return true
    }
    status = "语音密钥删除失败（\(result.status)），请重试。"
    return false
  }

  func stop() {
    generation = UUID()
    work?.cancel(); work = nil
    deadline?.cancel(); deadline = nil
    player?.stop(); player = nil
    busy = false
    ready = nil; failed = nil
    if status.contains("正在") { status = "朗读已停止。" }
  }

  nonisolated func audioPlayerDidFinishPlaying(
    _ player: AVAudioPlayer, successfully flag: Bool
  ) {
    Task { @MainActor in
      guard self.player === player else { return }
      self.player = nil
      self.status = flag ? "百炼复刻声音播放完成。" : "语音播放中断，请重试。"
    }
  }

  func speak(
    _ text: String, voice: String, onReady: (() -> Void)? = nil,
    onFailure: ((String) -> Void)? = nil
  ) {
    guard !isSpeakingOrPreparing else {
      onFailure?("已有语音正在播放。")
      return
    }
    let expanded = SpeechText.expandingCountdowns(text)
    stop()
    let token = generation
    ready = onReady
    failed = onFailure
    guard !expanded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      finishReady()
      return
    }
    deadline = Task {
      try? await Task.sleep(nanoseconds: 100_000_000_000)
      guard !Task.isCancelled, generation == token, busy else { return }
      fail("语音生成超过 100 秒，请检查网络、密钥和音色 ID。")
    }
    busy = true
    status = "正在生成百炼复刻语音…"
    work = Task {
      do {
        var key = cachedKey
        if key == nil {
          key = await Task.detached {
            CredentialVault.call("read", account: "cosyvoice").value
          }.value
        }
        try Task.checkCancellation()
        guard let key, !key.isEmpty else {
          throw VoiceFailure("尚未保存百炼语音 API Key。")
        }
        cachedKey = key
        let data = try await CosyVoiceAudio.generate(text: expanded, voice: voice, key: key)
        try Task.checkCancellation()
        guard generation == token else { return }
        let audio = try AVAudioPlayer(data: data)
        audio.delegate = self
        guard audio.prepareToPlay(), audio.play() else {
          throw VoiceFailure("语音已生成，但无法播放。")
        }
        player = audio
        busy = false
        status = "百炼复刻声音正在播放。"
        finishReady()
      } catch {
        guard generation == token, !Task.isCancelled else { return }
        fail(error.localizedDescription)
      }
    }
  }

  private func finishReady() {
    deadline?.cancel(); deadline = nil
    let callback = ready
    ready = nil; failed = nil
    callback?()
  }

  private func fail(_ message: String) {
    deadline?.cancel(); deadline = nil
    work?.cancel(); work = nil
    player?.stop(); player = nil
    busy = false
    status = "百炼语音不可用：\(message)"
    let callback = failed
    ready = nil; failed = nil
    callback?(message)
  }
}

struct VoiceFailure: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

enum CosyVoiceAudio {
  static func generate(text: String, voice: String, key: String) async throws -> Data {
    let voice = voice.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !voice.isEmpty else { throw VoiceFailure("缺少百炼复刻音色 ID。") }
    guard text.count <= 20_000 else { throw VoiceFailure("朗读内容过长，请分段朗读。") }
    let url = URL(
      string: "wss://ws-yr2r75chjfaphfr1.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference")!
    var request = URLRequest(url: url)
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 20
    let session = URLSession(configuration: .ephemeral)
    let socket = session.webSocketTask(with: request)
    socket.maximumMessageSize = 8 * 1024 * 1024
    socket.resume()
    defer {
      socket.cancel(with: .normalClosure, reason: nil)
      session.invalidateAndCancel()
    }
    let deadline = Task {
      try await Task.sleep(nanoseconds: 90_000_000_000)
      socket.cancel(with: .goingAway, reason: nil)
    }
    defer { deadline.cancel() }

    return try await withTaskCancellationHandler(operation: {
      let id = UUID().uuidString
      func send(_ action: String, _ payload: [String: Any]) async throws {
        let event: [String: Any] = [
          "header": ["action": action, "task_id": id, "streaming": "duplex"],
          "payload": payload,
        ]
        let data = try JSONSerialization.data(withJSONObject: event)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
      }
      try await send("run-task", [
        "task_group": "audio", "task": "tts", "function": "SpeechSynthesizer",
        "model": "cosyvoice-v3.5-flash", "input": [:],
        "parameters": [
          "text_type": "PlainText", "voice": voice, "format": "mp3",
          "sample_rate": 22_050, "volume": 50, "rate": 1.0, "pitch": 1.0,
          "language_hints": ["zh"],
        ],
      ])
      var audio = Data()
      var started = false
      while true {
        try Task.checkCancellation()
        switch try await socket.receive() {
        case .data(let chunk):
          audio.append(chunk)
          guard audio.count < 32 * 1024 * 1024 else {
            throw VoiceFailure("语音过长，请分段朗读。")
          }
        case .string(let json):
          guard
            let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
              as? [String: Any],
            let header = object["header"] as? [String: Any]
          else { throw VoiceFailure("语音服务返回格式异常。") }
          guard header["task_id"] as? String == id else { continue }
          switch header["event"] as? String {
          case "task-started":
            guard !started else { continue }
            started = true
            try await send("continue-task", ["input": ["text": text]])
            try await send("finish-task", ["input": [:]])
          case "task-finished":
            guard !audio.isEmpty else {
              throw VoiceFailure("服务没有返回音频，请检查音色与模型。")
            }
            return audio
          case "task-failed":
            let code = header["error_code"] as? String ?? "unknown"
            // Do not surface raw service messages; some providers echo input.
            throw VoiceFailure("百炼返回 \(code)，请检查密钥、余额及音色所属工作空间。")
          default:
            break
          }
        @unknown default:
          throw VoiceFailure("不支持的语音响应。")
        }
      }
    }, onCancel: {
      socket.cancel(with: .goingAway, reason: nil)
    })
  }
}

struct ClonedSpeechSettings: View {
  @ObservedObject var model: AppModel
  @ObservedObject var voice: ClonedSpeech
  @State private var key = ""

  var body: some View {
    Card {
      Text("语音播报与复刻声音（可选）").font(.headline)
      Toggle("语音播报总开关", isOn: Binding(
        get: { model.state.preferences.speechEnabled ?? true },
        set: {
          model.state.preferences.speechEnabled = $0
          model.stopSpeaking(); model.save()
        }))
      Toggle("朗读聊天回复", isOn: Binding(
        get: { model.state.preferences.spokenChatReplies ?? false },
        set: {
          model.state.preferences.spokenChatReplies = $0
          if !$0 { model.stopSpeaking() }
          model.save()
        }))
      Picker("朗读方式", selection: Binding(
        get: { model.state.preferences.clonedSpeechEnabled == true ? "bailian" : "system" },
        set: {
          model.state.preferences.clonedSpeechEnabled = $0 == "bailian"
          model.stopSpeaking(); model.save()
        })) {
        Text("macOS 系统声音（免费）").tag("system")
        Text("阿里云百炼复刻声音（自备 Key）").tag("bailian")
      }

      if model.state.preferences.clonedSpeechEnabled == true {
        TextField("百炼复刻音色 ID", text: Binding(
          get: { model.state.preferences.clonedVoiceID ?? "" },
          set: { model.state.preferences.clonedVoiceID = $0; model.save() }))
          .textFieldStyle(.roundedBorder)
        SecureField("百炼 API Key（留空不会覆盖）", text: $key)
          .textFieldStyle(.roundedBorder)
        HStack {
          Button("保存语音密钥") {
            let entered = key
            Task {
              if await voice.saveKey(entered) { key = "" }
            }
          }
          .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          Button("删除已存密钥", role: .destructive) {
            Task { _ = await voice.deleteKey() }
          }
          Button("试听") {
            model.speak("来啦。今天过得怎么样？", cloned: true)
          }
          .disabled(
            model.isSpeechActive
              || (model.state.preferences.clonedVoiceID ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          Button("停止") { model.stopSpeaking() }
        }
        Text("音色 ID 与 API Key 都需要你自己提供；公开程序不包含任何人的私有音色。若配置无效，会自动改用系统声音，文字聊天不受影响。")
          .font(.caption).foregroundStyle(.secondary)
        Text("使用复刻声音时，待朗读文字会发送到阿里云百炼，并按你的账户用量计费；密钥只保存在本机钥匙串，不进入备份。")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text("系统朗读不需要 API Key，也不会把待朗读文字发送到语音服务。")
          .font(.caption).foregroundStyle(.secondary)
      }
      Text(voice.status).font(.callout).textSelection(.enabled)
    }
  }
}
