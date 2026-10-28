import AppKit
import SwiftUI
import StillWithYouAssets

struct CharacterAssetPreviewStrip: View {
  @ObservedObject var model: AppModel

  private var previews: [(String, URL)] {
    [
      ("头像", model.characterAvatarURL),
      ("待机", model.characterActionURL("idle")),
      ("挥手", model.characterActionURL("wave")),
      ("跳起", model.characterActionURL("jump")),
      ("思考", model.characterActionURL("think")),
    ]
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ForEach(previews, id: \.0) { label, url in
        if let image = NSImage(contentsOf: url) {
          VStack(spacing: 7) {
            Image(nsImage: image)
              .resizable().scaledToFit()
              .frame(width: 104, height: 112)
              .background(Color.mist.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
              .clipShape(RoundedRectangle(cornerRadius: 12))
              .accessibilityLabel("\(label)预览")
            Text(label).font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .id(model.characterAssetRevision)
  }
}

private struct CharacterActionChoice: Identifiable, Hashable {
  let id: String
  let label: String
  let systemImage: String
  let row: Int

  static let all = [
    CharacterActionChoice(id: "idle", label: "待机", systemImage: "sparkles", row: 0),
    CharacterActionChoice(id: "run-right", label: "向右跑", systemImage: "arrow.right", row: 1),
    CharacterActionChoice(id: "run-left", label: "向左跑", systemImage: "arrow.left", row: 2),
    CharacterActionChoice(id: "wave", label: "挥手", systemImage: "hand.wave.fill", row: 3),
    CharacterActionChoice(id: "jump", label: "跳起", systemImage: "arrow.up", row: 4),
    CharacterActionChoice(id: "encourage", label: "鼓励", systemImage: "heart.fill", row: 5),
    CharacterActionChoice(id: "wait", label: "等待", systemImage: "hourglass", row: 6),
    CharacterActionChoice(id: "think", label: "思考", systemImage: "lightbulb.fill", row: 7),
    CharacterActionChoice(id: "review", label: "复盘", systemImage: "checkmark.circle.fill", row: 8),
    CharacterActionChoice(id: "look-a", label: "看左", systemImage: "eye.fill", row: 9),
    CharacterActionChoice(id: "look-b", label: "看右", systemImage: "eyes", row: 10),
  ]
}

struct CharacterAssetSettingsPanel: View {
  @ObservedObject var model: AppModel
  @State private var selectedAction = CharacterActionChoice.all[0]

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text("桌面照片角色").font(.headline)
          Text("在这里直接检查形象和每组动作。")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Picker("桌面人物模型", selection: Binding(
          get: { model.state.preferences.desktopCharacterID ?? "default" },
          set: { model.state.preferences.desktopCharacterID = $0; model.save(); model.refreshPet?() }
        )) {
          Text("内置抽象形象").tag("default")
          if model.hasCustomCharacter { Text("我的照片动画卡").tag("custom") }
        }
        .labelsHidden()
        .frame(width: 190)
      }

      if model.hasCustomCharacter {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: 24) { animatedPreview; actionPicker }
          VStack(alignment: .leading, spacing: 18) { animatedPreview; actionPicker }
        }

        HStack(spacing: 10) {
          Button(model.canAdjustCharacterPhoto ? "调整当前照片…" : "重新选择后调整…") {
            model.adjustCharacterPhoto()
          }
          .buttonStyle(.borderedProminent)
          Button("替换照片…") { model.importCharacterPhoto() }
          Text("更改前会先预览；取消不会覆盖现有形象。")
            .font(.caption).foregroundStyle(.secondary)
        }
      } else {
        HStack(spacing: 16) {
          Image(systemName: "person.crop.square.filled.and.at.rectangle")
            .font(.system(size: 42)).foregroundStyle(Color.lake)
            .frame(width: 88, height: 88)
            .background(Color.mist.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
          VStack(alignment: .leading, spacing: 8) {
            Text("还没有照片形象").font(.subheadline.weight(.semibold))
            Text("选择照片后会先预览取景，再生成 11 组动作。")
              .font(.caption).foregroundStyle(.secondary)
            Button("选择照片并预览…") { model.importCharacterPhoto() }
              .buttonStyle(.borderedProminent)
          }
        }
      }

      Text("图片只在本机处理。私人工作图仅用于以后调整取景，不会进入导出备份。")
        .font(.caption).foregroundStyle(.secondary)
    }
  }

  private var animatedPreview: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Text(selectedAction.label).font(.subheadline.weight(.semibold))
        Spacer()
        Label("8 帧预览", systemImage: "play.fill")
          .font(.caption2).foregroundStyle(.secondary)
      }
      AnimatedCharacterActionPreview(model: model, action: selectedAction)
        .frame(width: 286, height: 310)
    }
    .frame(width: 286)
  }

  private var actionPicker: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("选择要检查的动作").font(.subheadline.weight(.semibold))
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], spacing: 8) {
        ForEach(CharacterActionChoice.all) { action in
          Button {
            selectedAction = action
          } label: {
            Label(action.label, systemImage: action.systemImage)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, 10).padding(.vertical, 8)
              .background(
                selectedAction == action ? Color.lake.opacity(0.16) : Color.mist.opacity(0.55),
                in: RoundedRectangle(cornerRadius: 9))
              .overlay(
                RoundedRectangle(cornerRadius: 9)
                  .stroke(selectedAction == action ? Color.lake.opacity(0.8) : Color.clear))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("预览\(action.label)动作")
          .accessibilityAddTraits(selectedAction == action ? .isSelected : [])
        }
      }
    }
    .frame(minWidth: 290, maxWidth: 520, alignment: .leading)
  }
}

private struct AnimatedCharacterActionPreview: View {
  @ObservedObject var model: AppModel
  let action: CharacterActionChoice
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var frames: [NSImage] = []

  var body: some View {
    TimelineView(.animation(minimumInterval: 0.12, paused: reduceMotion || frames.count < 2)) { context in
      let index = reduceMotion || frames.isEmpty
        ? 0 : Int(context.date.timeIntervalSinceReferenceDate / 0.12) % frames.count
      Group {
        if frames.indices.contains(index) {
          Image(nsImage: frames[index]).resizable().scaledToFit()
        } else if let fallback = NSImage(contentsOf: model.characterActionURL(action.id)) {
          Image(nsImage: fallback).resizable().scaledToFit()
        } else {
          Image(systemName: "photo.badge.exclamationmark")
            .font(.system(size: 42)).foregroundStyle(.secondary)
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(
        LinearGradient(
          colors: [Color.mist.opacity(0.95), Color.lake.opacity(0.11)],
          startPoint: .topLeading, endPoint: .bottomTrailing),
        in: RoundedRectangle(cornerRadius: 18))
      .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.ink.opacity(0.08)))
    }
    .id("\(model.characterAssetRevision.uuidString)-\(action.id)")
    .onAppear(perform: reloadFrames)
    .onChange(of: action) { _, _ in reloadFrames() }
    .onChange(of: model.characterAssetRevision) { _, _ in reloadFrames() }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("当前照片形象，\(action.label)动作预览")
  }

  private func reloadFrames() {
    guard let sheet = NSImage(contentsOf: model.characterSpriteSheetURL),
      let cg = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil),
      cg.width % 8 == 0, cg.height % 11 == 0
    else {
      frames = []
      return
    }
    let frameWidth = cg.width / 8
    let frameHeight = cg.height / 11
    frames = (0..<8).compactMap { column in
      guard let crop = cg.cropping(to: CGRect(
        x: column * frameWidth, y: action.row * frameHeight,
        width: frameWidth, height: frameHeight))
      else { return nil }
      return NSImage(cgImage: crop, size: NSSize(width: 192, height: 208))
    }
  }
}

struct CharacterPhotoEditorView: View {
  @ObservedObject var model: AppModel
  let pending: PendingCharacterPhoto
  @State private var framing: CharacterFraming

  init(model: AppModel, pending: PendingCharacterPhoto) {
    self.model = model
    self.pending = pending
    _framing = State(initialValue: pending.initialFraming)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 5) {
        Text("预览并调整取景").font(.title2.weight(.semibold))
        Text(pending.sourceName).font(.caption).foregroundStyle(.secondary)
      }

      HStack(alignment: .center, spacing: 24) {
        VStack(alignment: .leading, spacing: 8) {
          Text("头像取景").font(.subheadline.weight(.semibold))
          Image(nsImage: CharacterAssetBuilder.framedPreview(
            from: pending.image, framing: framing))
            .resizable().scaledToFit()
            .frame(width: 280, height: 280)
            .background(Color.mist, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityLabel("调整后的头像取景预览")
        }
        VStack(alignment: .leading, spacing: 8) {
          Text("动作卡效果").font(.subheadline.weight(.semibold))
          Image(nsImage: CharacterAssetBuilder.actionPreview(
            from: pending.image, framing: framing, actionIndex: 3))
            .resizable().scaledToFit()
            .frame(width: 180, height: 195)
            .background(Color.mist.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityLabel("调整后的挥手动作卡预览")
          Text("生成后还会有待机、跑动、跳起、思考等 11 组动作卡。")
            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: 210, alignment: .leading)
        }
      }

      VStack(alignment: .leading, spacing: 12) {
        adjustmentRow("缩放", value: $framing.zoom, range: 1...3,
          valueText: String(format: "%.1f×", framing.zoom))
        adjustmentRow("水平位置", value: $framing.horizontal, range: -1...1,
          valueText: positionText(framing.horizontal, negative: "左", positive: "右"))
        adjustmentRow("垂直位置", value: $framing.vertical, range: -1...1,
          valueText: positionText(framing.vertical, negative: "上", positive: "下"))
      }

      Text("为便于以后再次调整，程序会在私人数据目录保留一份本机工作图；不会上传，也不会放进导出的备份。")
        .font(.caption).foregroundStyle(.secondary)

      HStack {
        Button("恢复默认取景") { framing = CharacterFraming() }
          .disabled(framing == CharacterFraming() || model.characterBusy)
        Spacer()
        Button("取消") { model.pendingCharacterPhoto = nil }
          .disabled(model.characterBusy)
        Button(model.characterBusy ? "正在生成…" : "使用此取景并生成") {
          model.commitCharacterPhoto(pending, framing: framing)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(model.characterBusy)
      }
    }
    .padding(26)
    .frame(width: 650)
  }

  private func adjustmentRow(
    _ title: String, value: Binding<Double>, range: ClosedRange<Double>, valueText: String
  ) -> some View {
    HStack(spacing: 12) {
      Text(title).frame(width: 72, alignment: .leading)
      Slider(value: value, in: range)
      Text(valueText).font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary).frame(width: 54, alignment: .trailing)
    }
  }

  private func positionText(_ value: Double, negative: String, positive: String) -> String {
    if abs(value) < 0.05 { return "居中" }
    return "\(value < 0 ? negative : positive) \(Int(abs(value) * 100))%"
  }
}
