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
    .sheet(item: $model.pendingPersonaDescriptionReview) { review in
      PersonaDescriptionReviewView(model: model, review: review)
        .interactiveDismissDisabled()
    }
    .sheet(item: $model.pendingCharacterPhoto) { pending in
      CharacterPhotoEditorView(model: model, pending: pending)
        .interactiveDismissDisabled(model.characterBusy)
    }
    .onChange(of: model.state.companion?.description) { _, value in
      profile.description = value ?? ""
    }
  }

  private var identityStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      setupHeader("步骤 1 · 名字与称呼", required: true,
        detail: "这是唯一必选步骤。这里只确定怎样称呼彼此；人物描述要等读取记录、确认说话人以后再生成。")
      Card {
        LabeledContent("对方的名字") { TextField("例如：阿岚", text: $profile.name).textFieldStyle(.roundedBorder) }
        LabeledContent("对方怎么称呼你") { TextField("例如：小周", text: $profile.userName).textFieldStyle(.roundedBorder) }
        Divider()
        Text("固定边界").font(.subheadline.weight(.semibold))
        Label("始终标明这是记录驱动的模拟，不是现实人物本人", systemImage: "person.crop.circle.badge.exclamationmark")
        Label("没有证据就不编造共同经历，也不夸大关系", systemImage: "checkmark.shield")
        Label("AI 提出的描述必须由你查看、修改并确认后才生效", systemImage: "pencil.and.list.clipboard")
        Text("这些边界由程序执行，不需要写进人物描述。")
          .font(.caption).foregroundStyle(.secondary)
      }
      nextButton("保存并继续") {
        guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !profile.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
          model.saveIdentity(profile)
          return
        }
        model.saveIdentity(profile)
        move(to: 2)
      }
    }
  }

  private var photoStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      setupHeader("步骤 2 · 桌面形象", required: false,
        detail: "选一张照片，先预览并调整取景，再生成头像与 11 组轻动画卡。它不会用 AI 改姿势；也可以直接使用内置抽象形象。")
      Card {
        Label(model.hasCustomCharacter ? "已生成本机动作包" : "尚未添加照片",
          systemImage: model.hasCustomCharacter ? "checkmark.seal.fill" : "photo.badge.plus")
          .font(.headline).foregroundStyle(model.hasCustomCharacter ? Color.moss : Color.ink)
        if model.hasCustomCharacter {
          CharacterAssetPreviewStrip(model: model)
          Text("上面就是桌面实际使用的头像与动作卡预览。觉得取景不合适，可以调整或换一张照片；确认前不会覆盖当前形象。")
            .font(.caption).foregroundStyle(.secondary)
        } else {
          Text("选择后会先预览，可以缩放和移动取景；满意后再生成，不会直接覆盖。")
            .font(.caption).foregroundStyle(.secondary)
        }
        Text("图片不会上传；为再次调整取景，私人数据目录会保留一份本机工作图，导出的备份不包含它。")
          .font(.caption).foregroundStyle(.secondary)
        HStack {
          if model.hasCustomCharacter {
            Button(model.canAdjustCharacterPhoto ? "调整取景…" : "重新选择后调整…") {
              model.adjustCharacterPhoto()
            }
          }
          Button(model.hasCustomCharacter ? "换一张照片…" : "选择照片并预览…") {
            model.importCharacterPhoto()
          }.buttonStyle(.borderedProminent)
        }
      }
      navigation(optionalDone: model.hasCustomCharacter, next: 3)
    }
  }

  private var memoryStep: some View {
    VStack(alignment: .leading, spacing: 18) {
      setupHeader("步骤 3 · 聊天与记忆", required: false,
        detail: "可一次选多个 TXT、Markdown、JSON、JPG/PNG、Word 或 PDF。图片与扫描 PDF 在本机 OCR；原文与可选总结分开保存，导入后由你确认聊天中的哪一位是对方。")
      Card {
        Label("\(model.state.historicalRecords?.count ?? 0) 条原始片段 · \(model.effectiveKnowledge.memories.count) 张可选总结",
          systemImage: "text.book.closed")
          .font(.headline)
        Text("导入不会强制生成描述或总结。AI 可以给出说话人建议，但必须由你确认；候选不对时可取消并撤销本次导入。")
          .font(.caption).foregroundStyle(.secondary)
        Button("导入聊天记录…") { model.importHistory() }
          .buttonStyle(.borderedProminent).disabled(model.historySpeakerDetectionBusy)
      }
      personaDraftCard
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
      if model.confirmedHistoryRecordCount > 0 { personaDraftCard }
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

  private var personaDraftCard: some View {
    Card {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("人物描述草案").font(.headline)
          Text(profile.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "尚未确认人物描述" : "已有经你确认的人物描述")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Text("\(model.confirmedHistoryRecordCount) 条已确认原话")
          .font(.caption).foregroundStyle(.secondary)
      }
      Text("导入后先确认哪位是对方。AI 只会生成一份可编辑草案，必须由你确认后才会用于聊天。")
        .font(.caption).foregroundStyle(.secondary)
      Button(model.personaDescriptionBusy ? "正在生成草案…" : "从已确认记录生成草案") {
        Task { await model.generatePersonaDescriptionDraft() }
      }
      .buttonStyle(.borderedProminent)
      .disabled(model.personaDescriptionBusy || !model.apiReady
        || model.confirmedHistoryRecordCount == 0)
      if !model.apiReady {
        Text("尚未配置 AI。可以先完成导入；连接 AI 后再生成，或进入设置手动填写。")
          .font(.caption).foregroundStyle(.secondary)
      } else if model.confirmedHistoryRecordCount == 0 {
        Text("先导入记录，并在识别窗口中确认哪一位是对方。")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text("本次会发送最多 120 条、共 24,000 字的对方原话抽样，可能产生少量 API 费用。")
          .font(.caption).foregroundStyle(.secondary)
      }
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
