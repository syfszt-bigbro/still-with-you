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
