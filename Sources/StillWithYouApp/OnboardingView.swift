import SwiftUI
import StillWithYouCore

struct OnboardingView: View {
  @ObservedObject var model: AppModel
  @State private var profile = CompanionProfile()
  @State private var apiKey = ""

  private var setup: OnboardingState { model.state.onboarding ?? OnboardingState() }
  private var step: Int { setup.currentStep }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 6) {
          Text("她一直都在").font(.system(size: 34, weight: .medium, design: .serif))
          Text("Still With You · 先完成 1 个必选步骤，其余都可以以后再做")
            .font(.callout).foregroundStyle(.secondary)
        }
        Spacer()
        Text("\(step) / 4").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
      }.padding(30)
      HStack(spacing: 8) {
        ForEach(1...4, id: \.self) { item in
          Capsule().fill(item <= step ? Color.lake : Color.ink.opacity(0.10)).frame(height: 5)
        }
      }.padding(.horizontal, 30)

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          switch step {
          case 1: identityStep
          case 2: photoStep
          case 3: memoryStep
          default: connectionStep
          }
        }.padding(30)
      }
    }
    .frame(minWidth: 720, idealWidth: 780, minHeight: 600, idealHeight: 700)
    .background(Color.mist)
    .onAppear { profile = model.profile }
    .interactiveDismissDisabled(true)
    .sheet(item: $model.pendingHistorySpeakerReview) { review in
      HistorySpeakerReviewView(model: model, review: review)
        .interactiveDismissDisabled()
    }
  }

  private var identityStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      setupHeader("步骤 1 · 名字与边界", required: true,
        detail: "这是唯一必选步骤。先确定怎样称呼彼此，以及这个角色绝不能越过的边界。")
      Card {
        LabeledContent("对方的名字") { TextField("例如：阿岚", text: $profile.name).textFieldStyle(.roundedBorder) }
        LabeledContent("对方怎么称呼你") { TextField("例如：小周", text: $profile.userName).textFieldStyle(.roundedBorder) }
        Text("人物描述与边界").font(.subheadline)
        TextField("例如：说话简短、有主见；只模拟聊天风格，不冒充真人；不夸大关系。",
          text: $profile.description, axis: .vertical)
          .lineLimit(5...9).textFieldStyle(.roundedBorder)
        Text("程序会始终标明这是记录驱动的模拟，不是现实人物本人。")
          .font(.caption).foregroundStyle(.secondary)
      }
      nextButton("保存并继续") {
        model.saveProfile(profile)
        guard !profile.displayName.isEmpty, !profile.displayUserName.isEmpty else { return }
        move(to: 2)
      }
    }
  }

  private var photoStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      setupHeader("步骤 2 · 桌面形象", required: false,
        detail: "选一张照片，程序会在本机保留完整画面，生成头像与 11 组轻动画卡。它不会用 AI 改姿势；也可以直接使用内置抽象形象。")
      Card {
        Label(model.hasCustomCharacter ? "已生成本机动作包" : "尚未添加照片",
          systemImage: model.hasCustomCharacter ? "checkmark.seal.fill" : "photo.badge.plus")
          .font(.headline).foregroundStyle(model.hasCustomCharacter ? Color.moss : Color.ink)
        Text("图片不会自动上传；原图不会被复制进资料库，只保存生成后的头像和动作 PNG。")
          .font(.caption).foregroundStyle(.secondary)
        Button(model.hasCustomCharacter ? "重新选择照片并生成" : "选择照片并生成动作包…") {
          model.importCharacterPhoto()
        }.buttonStyle(.borderedProminent)
      }
      navigation(optionalDone: model.hasCustomCharacter, next: 3)
    }
  }

  private var memoryStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      setupHeader("步骤 3 · 聊天与记忆", required: false,
        detail: "导入 TXT、Markdown、JSON 或 JSONL。原文与可选总结分开保存；导入后由你确认聊天中的哪一位是对方。")
      Card {
        Label("\(model.state.historicalRecords?.count ?? 0) 条原始片段 · \(model.effectiveKnowledge.memories.count) 张可选总结",
          systemImage: "text.book.closed")
          .font(.headline)
        Text("导入不会强制生成描述或总结。AI 可以给出说话人建议，但必须由你确认；已有总结可在“记忆”页替换或删除，原文不受影响。")
          .font(.caption).foregroundStyle(.secondary)
        Button("导入聊天记录…") { model.importHistory() }
          .buttonStyle(.borderedProminent).disabled(model.historySpeakerDetectionBusy)
      }
      navigation(optionalDone: setup.memoryConfigured, next: 4)
    }
  }

  private var connectionStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      setupHeader("步骤 4 · AI 连接与语音", required: false,
        detail: "不配置也能使用桌面互动、计划、计时、导入、记忆与备份。语音默认使用 macOS 系统朗读。")
      Card {
        Picker("AI 服务商", selection: Binding(
          get: { model.state.preferences.resolvedAIProvider.rawValue },
          set: { value in
            model.state.preferences.aiProvider = value
            if value == AIProviderPreset.deepseek.rawValue { model.state.preferences.model = "deepseek-chat" }
            if value == AIProviderPreset.openai.rawValue { model.state.preferences.model = "gpt-4.1-mini" }
            model.save()
          }
        )) {
          ForEach(AIProviderPreset.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
        }
        if model.state.preferences.resolvedAIProvider == .openAICompatible {
          TextField("完整 chat/completions 地址", text: Binding(
            get: { model.state.preferences.aiEndpoint ?? "" },
            set: { model.state.preferences.aiEndpoint = $0; model.save() }
          )).textFieldStyle(.roundedBorder)
        }
        TextField("模型名称", text: $model.state.preferences.model).textFieldStyle(.roundedBorder)
        SecureField("API Key", text: $apiKey).textFieldStyle(.roundedBorder)
        HStack {
          Button("保存并测试") {
            do {
              try Secrets.set("chat-api", apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
              apiKey = ""
              model.state.preferences.aiEnabled = true; model.save()
              Task { await model.testAPI() }
            } catch { model.notice = error.localizedDescription }
          }.disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.state.preferences.model.isEmpty)
          if setup.apiConfigured { Label("连接已验证", systemImage: "checkmark.circle.fill").foregroundStyle(Color.moss) }
        }
        Text("测试会发送一句最短请求，可能产生极少量 API 费用。密钥只保存在 macOS 钥匙串，不进入备份。")
          .font(.caption).foregroundStyle(.secondary)
      }
      ClonedSpeechSettings(model: model, voice: model.clonedSpeech)
      Card {
        Text("写在最后").font(.title3.weight(.semibold))
        Text("你喜欢过的人，不论你们有没有真正走到一起，也不论那段同行持续了多久，都可能在你身上留下不可磨灭的痕迹。\n\n这个程序不是为了把谁困在过去，也不是让一段模拟替代真实的人。它只是帮你把那些聊天、照片、习惯和片段妥善收好，让你有机会看清：那段情感给过你什么，你又因此成为了怎样的人。\n\n我们不应把记忆变成执念。真正好的情感，即使没有结局，也应当让人更坦荡、更温柔、更有勇气向前。愿你保存那些照亮过你的部分，也把自己带往更明亮的生活。\n\n这就是“她一直都在”的初衷：不是让她永远停在这里，而是让被她改变过的你，继续向阳而行。")
          .font(.body).lineSpacing(5).foregroundStyle(Color.ink.opacity(0.82))
      }
      HStack {
        Button("上一步") { move(to: 3) }
        Spacer()
        Button(setup.apiConfigured ? "完成配置" : "暂不配置 API，进入程序") { finish() }
          .buttonStyle(.borderedProminent)
      }
    }
  }

  private func setupHeader(_ title: String, required: Bool, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack { Text(title).font(.system(size: 26, weight: .medium, design: .serif)); Text(required ? "必选" : "可选").font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 4).background((required ? Color.apricot : Color.lake).opacity(0.18), in: Capsule()) }
      Text(detail).foregroundStyle(.secondary)
    }
  }

  private func navigation(optionalDone: Bool, next: Int) -> some View {
    HStack {
      Button("上一步") { move(to: max(1, next - 2)) }
      Spacer()
      Button(optionalDone ? "继续" : "跳过，稍后设置") { move(to: next) }.buttonStyle(.borderedProminent)
    }
  }

  private func nextButton(_ title: String, action: @escaping () -> Void) -> some View {
    HStack { Spacer(); Button(title, action: action).buttonStyle(.borderedProminent) }
  }

  private func move(to step: Int) {
    if model.state.onboarding == nil { model.state.onboarding = OnboardingState() }
    model.state.onboarding?.currentStep = step
    model.save()
  }

  private func finish() {
    if model.state.onboarding == nil { model.state.onboarding = OnboardingState() }
    model.state.onboarding?.identityCompleted = true
    model.state.onboarding?.completed = true
    model.save()
  }
}
