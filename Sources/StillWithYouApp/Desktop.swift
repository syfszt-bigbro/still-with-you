import AppKit
import Combine
import SwiftUI
import UserNotifications
import StillWithYouCore

final class FloatingPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
private struct ReachAnimation: Decodable {
  var frameCount: Int
  var durations: [Double]
  var fingertipX: Double
  var fingertipY: Double
}
@MainActor final class SpriteView: NSView {
  let model: AppModel
  var frames: [[NSImage]] = []
  var frameBitmaps: [[NSBitmapImageRep]] = []
  private var staticCharacter: NSImage?
  private var staticCharacterBitmap: NSBitmapImageRep?
  private var reachAnimation: ReachAnimation?
  private var reachStarted: Double?
  private var reachMirrored = false
  var row = 0, col = 0
  var rowSince = Date()
  var currentState = "idle"
  private var loadedCharacterRevision: String?
  var dragOrigin: NSPoint?
  var pointerOrigin: NSPoint?
  var moved = false
  var interactions = PetInteractions()
  var lastDragX: CGFloat?
  var onMove: (() -> Void)?
  var onDrop: ((NSRect?) -> Void)?
  var originalScreen: NSRect?
  var onClick: (() -> Void)?
  var menuAction: ((String) -> Void)?
  let timings: [[Double]] = [
    [0.28, 0.11, 0.11, 0.14, 0.14, 0.32], [0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.22],
    [0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.22], [0.14, 0.14, 0.14, 0.28],
    [0.14, 0.14, 0.14, 0.14, 0.28], [0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.14, 0.24],
    [0.15, 0.15, 0.15, 0.15, 0.15, 0.26], [0.12, 0.12, 0.12, 0.12, 0.12, 0.22],
    [0.15, 0.15, 0.15, 0.15, 0.15, 0.28],
  ]
  init(model: AppModel) {
    self.model = model
    super.init(frame: .zero)
    wantsLayer = true
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel("桌面陪伴者：单击聊天，拖动移动，右键查看动作")
    loadCharacterAssets()
  }
  func loadCharacterAssets() {
    let selected = model.state.preferences.desktopCharacterID ?? "default"
    let resource: String
    switch selected {
    case "custom": resource = "custom-spritesheet"
    default: resource = "default-spritesheet"
    }
    let local = model.directory.appendingPathComponent("character/\(resource).png")
    let revision = (try? CharacterAssetRevision.cacheKey(
      selection: selected, customAssetURL: local)) ?? selected
    guard loadedCharacterRevision != revision else { return }
    loadedCharacterRevision = revision
    frames.removeAll(); frameBitmaps.removeAll(); reachAnimation = nil
    staticCharacter = nil; staticCharacterBitmap = nil
    row = 0; col = 0; currentState = "idle"; rowSince = Date()
    let packagedBundle = Bundle.main.url(
      forResource: "StillWithYou_StillWithYouApp", withExtension: "bundle"
    ).flatMap(Bundle.init(url:))
    let url = selected == "custom" && FileManager.default.fileExists(atPath: local.path)
      ? local : (packagedBundle?.url(forResource: resource, withExtension: "png")
        ?? Bundle.module.url(forResource: resource, withExtension: "png"))
    if let url,
      let image = NSImage(contentsOf: url),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.width == 1536,
      cg.height == 2288
    {
      for r in 0..<11 {
        var line: [NSImage] = []
        var bits: [NSBitmapImageRep] = []
        for c in 0..<8 {
          if let crop = cg.cropping(to: CGRect(x: c * 192, y: r * 208, width: 192, height: 208)) {
            line.append(NSImage(cgImage: crop, size: NSSize(width: 192, height: 208)))
            bits.append(NSBitmapImageRep(cgImage: crop))
          }
        }
        frames.append(line)
        frameBitmaps.append(bits)
      }
    }
    if selected == "default", frames.count == 11,
      let metadataURL = Bundle.main.url(forResource: "reach-right", withExtension: "json"),
      let data = try? Data(contentsOf: metadataURL),
      let metadata = try? JSONDecoder().decode(ReachAnimation.self, from: data),
      metadata.frameCount > 0, metadata.frameCount <= 8,
      metadata.durations.count == metadata.frameCount,
      metadata.durations.allSatisfy({ $0 > 0 && $0 <= 2 }),
      (0...192).contains(metadata.fingertipX), (0...208).contains(metadata.fingertipY),
      let url = Bundle.main.url(forResource: "reach-right", withExtension: "png"),
      let image = NSImage(contentsOf: url),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      cg.width == metadata.frameCount * 192, cg.height == 208 {
      var line: [NSImage] = []
      var bits: [NSBitmapImageRep] = []
      for index in 0..<metadata.frameCount {
        if let crop = cg.cropping(to: CGRect(x: index * 192, y: 0, width: 192, height: 208)) {
          line.append(NSImage(cgImage: crop, size: NSSize(width: 192, height: 208)))
          bits.append(NSBitmapImageRep(cgImage: crop))
        }
      }
      if line.count == metadata.frameCount { frames.append(line); frameBitmaps.append(bits); reachAnimation = metadata }
    }
  }
  required init?(coder: NSCoder) { fatalError() }
  override var isOpaque: Bool { false }
  func updateAnimation() {
    let now = ProcessInfo.processInfo.systemUptime
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    if dragOrigin != nil || model.busy || reduceMotion {
      reachStarted = nil; interactions.resetReach()
    }
    if let start = reachStarted, let animation = reachAnimation, (now - start) / 1.6 >= animation.durations.reduce(0, +) { reachStarted = nil }
    var state = reachStarted == nil ? model.gesture : "reach"
    if dragOrigin != nil {
      state = currentState
    } else if model.busy {
      state = "running"
    } else if model.state.timer?.awaitingReflection == true && reachStarted == nil {
      state = "waiting"
    }
    if state != currentState {
      currentState = state
      rowSince = Date()
    }
    let names = [
      "idle", "running-right", "running-left", "waving", "jumping", "failed", "waiting", "running",
      "review",
    ]
    row = state == "reach" ? 11 : names.firstIndex(of: state) ?? 0
    if let w = window, w.isVisible, dragOrigin == nil {
      let mouse = NSEvent.mouseLocation
      // Keep sampling pointer regions even while a reply is speaking or being
      // generated. PetInteractions must observe that the cursor stayed put;
      // otherwise the next frame after speech resets its dwell and repeats it.
      if !reduceMotion, reachAnimation != nil, bounds.width > 0, bounds.height > 0 {
        let x = (mouse.x - w.frame.midX) / bounds.width * 192
        let y = (mouse.y - w.frame.midY) / bounds.height * 208
        if let reaction = interactions.proximity(x: x, y: y, at: now) {
          if model.canAcceptPetReaction, !model.busy {
            if reaction == .reach {
              reachMirrored = x < 0
              reachStarted = now
            }
            model.reactToPet(reaction)
          }
        }
      }
      // Users circle the head, not the center of the full-body window.
      let head = NSPoint(x: w.frame.midX, y: w.frame.minY + w.frame.height * 0.84)
      if let reaction = interactions.pointer(x: mouse.x - head.x, y: mouse.y - head.y, at: now, includeHover: false) {
        model.reactToPet(reaction)
      }
    } else { interactions.resetPointer() }
    if reduceMotion {
      row = 0
      col = 0
    } else if row == 0, let w = window {
      let mouse = NSEvent.mouseLocation
      let center = NSPoint(x: w.frame.midX, y: w.frame.midY)
      let dx = mouse.x - center.x
      let dy = mouse.y - center.y
      // Distant pointers don't keep her staring; head look is local and opt-in by proximity.
      if hypot(dx, dy) > 75 && hypot(dx, dy) < 550 {
        var angle = atan2(dx, dy)
        if angle < 0 { angle += 2 * .pi }
        let dir = Int((angle / (2 * .pi) * 16).rounded()) % 16
        row = 9 + dir / 8
        col = dir % 8
      } else {
        advanceFrame()
      }
    } else {
      advanceFrame()
    }
    needsDisplay = true
    if let w = window, dragOrigin == nil {
      let local = convert(w.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
      w.ignoresMouseEvents = !opaqueAt(local)
    }
  }
  func advanceFrame() {
    if row == 11, let animation = reachAnimation, let start = reachStarted {
      var elapsed = (ProcessInfo.processInfo.systemUptime - start) / 1.6
      col = animation.frameCount - 1
      for (index, duration) in animation.durations.enumerated() {
        if elapsed < duration { col = index; break }
        elapsed -= duration
      }
      return
    }
    // Reach may be interrupted by a click/drag before its next frame. Its
    // sprite row is not an index into the ordinary animation timing table.
    guard timings.indices.contains(row) else {
      row = 0; col = 0; currentState = "idle"; rowSince = Date()
      return
    }
    let times = timings[row]
    var time = Date().timeIntervalSince(rowSince).truncatingRemainder(
      dividingBy: times.reduce(0, +))
    col = times.count - 1
    for (i, d) in times.enumerated() {
      if time < d {
        col = min(i, 7)
        break
      }
      time -= d
    }
  }
  func opaqueAt(_ point: NSPoint) -> Bool {
    if let staticCharacterBitmap, let imageRect = staticCharacterRect {
      guard imageRect.contains(point), imageRect.width > 0, imageRect.height > 0 else { return false }
      let x = min(staticCharacterBitmap.pixelsWide - 1, max(0, Int((point.x - imageRect.minX) / imageRect.width * CGFloat(staticCharacterBitmap.pixelsWide))))
      let y = min(staticCharacterBitmap.pixelsHigh - 1, max(0, Int((1 - (point.y - imageRect.minY) / imageRect.height) * CGFloat(staticCharacterBitmap.pixelsHigh))))
      return (staticCharacterBitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.15
    }
    guard bounds.contains(point), frameBitmaps.count > row, frameBitmaps[row].count > col,
      bounds.width > 0, bounds.height > 0
    else { return false }
    let rawX = min(191, max(0, Int(point.x / bounds.width * 192)))
    let x = row == 11 && reachMirrored ? 191 - rawX : rawX
    let y = min(207, max(0, Int((1 - point.y / bounds.height) * 208)))
    return (frameBitmaps[row][col].colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.15
  }
  override func draw(_ dirtyRect: NSRect) {
    if let staticCharacter, let imageRect = staticCharacterRect {
      NSGraphicsContext.current?.imageInterpolation = .high
      staticCharacter.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
      drawSleepCueIfNeeded()
      return
    }
    guard frames.count > row, frames[row].count > col else { return }
    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.saveGraphicsState()
    if row == 11 && reachMirrored {
      let transform = NSAffineTransform()
      transform.translateX(by: bounds.width, yBy: 0)
      transform.scaleX(by: -1, yBy: 1)
      transform.concat()
    }
    frames[row][col].draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    drawSleepCueIfNeeded()
  }
  private func drawSleepCueIfNeeded() {
    let characterID = model.state.preferences.desktopCharacterID ?? "default"
    guard characterID == "default", CompanionSchedule.isSleeping(at: Date()) else { return }
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.white.withAlphaComponent(0.95)
    shadow.shadowBlurRadius = 5
    shadow.shadowOffset = NSSize(width: 1, height: -1)
    let fontSize = min(34, max(19, bounds.height * 0.08))
    let mark = NSAttributedString(string: "Zzz", attributes: [
      .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
      .foregroundColor: NSColor(calibratedRed: 0.31, green: 0.50, blue: 0.75, alpha: 0.96),
      .shadow: shadow,
    ])
    mark.draw(at: NSPoint(x: bounds.midX + bounds.width * 0.08, y: bounds.height * 0.83))
  }
  private var staticCharacterRect: NSRect? {
    guard staticCharacter != nil, bounds.width > 0, bounds.height > 0 else { return nil }
    let imageAspect = CGFloat(2.0 / 3.0)
    let size = NSSize(width: min(bounds.width, bounds.height * imageAspect), height: min(bounds.height, bounds.width / imageAspect))
    return NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
  }
  override func mouseDown(with event: NSEvent) {
    reachStarted = nil
    interactions.resetReach()
    currentState = "idle"; row = 0; col = 0; rowSince = Date()
    originalScreen = window?.screen?.frame
    pointerOrigin = NSEvent.mouseLocation
    dragOrigin = window?.frame.origin
    moved = false
    lastDragX = pointerOrigin?.x
    if let pointerOrigin { interactions.beginDrag(x: pointerOrigin.x, y: pointerOrigin.y, at: ProcessInfo.processInfo.systemUptime) }
  }
  override func mouseDragged(with event: NSEvent) {
    guard let start = pointerOrigin, let origin = dragOrigin else { return }
    let now = NSEvent.mouseLocation
    let dx = now.x - start.x
    let dy = now.y - start.y
    if abs(dx) + abs(dy) > 3 { moved = true }
    let movementX = now.x - (lastDragX ?? start.x)
    lastDragX = now.x
    let newState = movementX >= 0 ? "running-right" : "running-left"
    if let reaction = interactions.drag(x: now.x, y: now.y, at: ProcessInfo.processInfo.systemUptime) { model.reactToPet(reaction) }
    if currentState != newState {
      currentState = newState
      rowSince = Date()
    }
    window?.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
    onMove?()
  }
  override func mouseUp(with event: NSEvent) {
    dragOrigin = nil
    pointerOrigin = nil
    lastDragX = nil
    if moved { onDrop?(originalScreen) }
    originalScreen = nil
    interactions.endDrag()
    model.gesture = "idle"
    if !moved { onClick?() }
    onMove?()
  }
  override func rightMouseDown(with event: NSEvent) {
    let menu = NSMenu()
    for (title, action) in [
      ("和\(model.companionName)聊聊", "chat"), ("今天的计划", "main"), ("招手", "waving"), ("跳一下", "jumping"), ("等待", "waiting"),
      ("思考", "running"), ("看看记录", "review"), ("暂时隐藏", "hide"), ("退出", "quit"),
    ] {
      let item = NSMenuItem(title: title, action: #selector(handleMenu(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = action
      menu.addItem(item)
    }
    NSMenu.popUpContextMenu(menu, with: event, for: self)
  }
  @objc func handleMenu(_ item: NSMenuItem) {
    if let action = item.representedObject as? String { menuAction?(action) }
  }
}
// The standalone AppKit window must invalidate its hosted chat tree when the
// shared transcript changes, even after it has been hidden or inactive.
private struct DesktopChatRoot: View {
  let model: AppModel
  let revision: UUID
  var body: some View { ChatView(model: model, compact: true).id(revision) }
}

@MainActor final class DesktopController {
  let model: AppModel
  let pet: FloatingPanel
  let hud: FloatingPanel
  let chat: NSWindow
  let sprite: SpriteView
  var animationTimer: Timer?
  private var transcriptSubscription: AnyCancellable?
  private var chatHost: NSHostingView<DesktopChatRoot>?
  init(model: AppModel) {
    self.model = model
    sprite = SpriteView(model: model)
    pet = FloatingPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    hud = FloatingPanel(
      contentRect: NSRect(x: 0, y: 0, width: 270, height: 159),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    chat = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 380, height: 540),
      styleMask: [.titled, .closable, .resizable], backing: .buffered,
      defer: false)
    for panel in [pet, hud] {
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = false
      panel.hidesOnDeactivate = false
      panel.isReleasedWhenClosed = false
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    pet.contentView = sprite
    pet.title = "她一直都在 · 桌面伙伴"
    hud.contentView = NSHostingView(rootView: PetHUD(model: model))
    hud.title = "她一直都在 · 计时"
    let chatHost = NSHostingView(rootView: DesktopChatRoot(model: model, revision: UUID()))
    self.chatHost = chatHost
    chat.contentView = chatHost
    transcriptSubscription = model.$chatMessages.dropFirst()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.refreshChatTranscript() }
    chat.title = "她一直都在 · 对话"
    chat.isReleasedWhenClosed = false
    chat.hidesOnDeactivate = false
    chat.minSize = NSSize(width: 340, height: 400)
    chat.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    sprite.onMove = { [weak self] in
      self?.positionHUD()
    }
    sprite.onDrop = { [weak self] original in
      guard let self else { return }
      self.clampToScreen()
      self.positionHUD()
      self.savePosition()
      guard let screen = self.pet.screen else { return }
      let area = screen.visibleFrame
      let horizontal = max(1, area.width - self.pet.frame.width)
      let vertical = max(1, area.height - self.pet.frame.height - 115)
      let x = (self.pet.frame.minX - area.minX) / horizontal
      let y = (self.pet.frame.minY - area.minY - 115) / vertical
      if let event = self.sprite.interactions.drop(x: x, y: y,
        crossedScreen: original.map { $0 != screen.frame } ?? false,
        at: ProcessInfo.processInfo.systemUptime) { self.model.reactToPet(event) }
    }
    sprite.onClick = { [weak self] in self?.toggleChat() }
    sprite.menuAction = { [weak self] action in self?.menu(action) }
    resize()
    let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
    let defaults = UserDefaults.standard
    let origin =
      defaults.object(forKey: "petX") != nil
      ? NSPoint(x: defaults.double(forKey: "petX"), y: defaults.double(forKey: "petY"))
      : NSPoint(x: screen.maxX - pet.frame.width - 35, y: screen.minY + 90)
    pet.setFrameOrigin(origin)
    clampToScreen()
    positionHUD()
    show()
    animationTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.sprite.updateAnimation() }
    }
    if let animationTimer { RunLoop.main.add(animationTimer, forMode: .common) }
    NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.clampToScreen()
        self?.positionHUD()
      }
    }
  }
  func resize() {
    pet.title = "\(model.companionName)桌面伙伴"
    hud.title = "\(model.companionName)计时"
    chat.title = "\(model.companionName) · 聊一会儿"
    sprite.setAccessibilityLabel("\(model.companionName)桌面人物：单击聊天，拖动移动，右键查看动作")
    let height = model.state.preferences.petHeight
    let isIntroWoman = model.state.preferences.desktopCharacterID == "intro-woman"
    pet.setContentSize(NSSize(width: height * (isIntroWoman ? 2.0 / 3.0 : 192.0 / 208.0), height: height))
    for p in [pet, hud, chat] {
      p.level = model.state.preferences.alwaysOnTop ? .floating : .normal
    }
    clampToScreen()
    positionHUD()
  }
  func clampToScreen() {
    let center = NSPoint(x: pet.frame.midX, y: pet.frame.midY)
    let screen = NSScreen.screens.first { $0.visibleFrame.contains(center) }
      ?? NSScreen.screens.first { $0.visibleFrame.intersects(pet.frame) } ?? NSScreen.main
    guard let f = screen?.visibleFrame else { return }
    pet.setFrameOrigin(
      NSPoint(
        x: min(max(pet.frame.minX, f.minX), f.maxX - pet.frame.width),
        y: min(max(pet.frame.minY, f.minY + 115), f.maxY - pet.frame.height)))
  }
  func positionHUD() {
    hud.setFrameOrigin(
      NSPoint(x: pet.frame.midX - hud.frame.width / 2, y: pet.frame.minY - hud.frame.height + 30))
  }
  func savePosition() {
    UserDefaults.standard.set(pet.frame.minX, forKey: "petX")
    UserDefaults.standard.set(pet.frame.minY, forKey: "petY")
  }
  func show() {
    pet.orderFrontRegardless()
    hud.orderFrontRegardless()
  }
  private func refreshChatTranscript() {
    chatHost?.rootView = DesktopChatRoot(model: model, revision: UUID())
  }
  func openChat() {
    refreshChatTranscript()
    if !chat.isVisible { toggleChat() }
    else { chat.makeKeyAndOrderFront(nil) }
    NSApp.activate(ignoringOtherApps: true)
    model.chatFocusRequest = UUID()
  }
  func toggleChat() {
    if !chat.isVisible { refreshChatTranscript() }
    if chat.isVisible {
      chat.orderOut(nil)
    } else {
      let screen = pet.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
      let x =
        pet.frame.midX > screen.midX ? pet.frame.minX - chat.frame.width + 60 : pet.frame.maxX - 60
      chat.setFrameOrigin(
        NSPoint(
          x: min(max(x, screen.minX), screen.maxX - chat.frame.width),
          y: min(max(pet.frame.minY, screen.minY), screen.maxY - chat.frame.height)))
      chat.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      model.chatFocusRequest = UUID()
    }
  }
  func menu(_ action: String) {
    switch action {
    case "chat": toggleChat()
    case "main": model.showMain?()
    case "hide":
      pet.orderOut(nil)
      hud.orderOut(nil)
      chat.orderOut(nil)
    case "quit": NSApp.terminate(nil)
    default: model.animate(action)
    }
  }
}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  var model: AppModel!
  var desktop: DesktopController!
  var mainWindow: NSWindow!
  var status: NSStatusItem!
  func applicationDidFinishLaunching(_ notification: Notification) {
    installMenus()
    UNUserNotificationCenter.current().delegate = self
    model = AppModel()
    mainWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    mainWindow.title = "\(model.companionName) · \(model.userName)的一天"
    mainWindow.contentView = NSHostingView(rootView: MainView(model: model))
    mainWindow.isReleasedWhenClosed = false
    mainWindow.center()
    mainWindow.setFrameAutosaveName("StillWithYouMain")
    model.showMain = { [weak self] in self?.openMain() }
    desktop = DesktopController(model: model)
    model.showChat = { [weak self] in self?.desktop.openChat() }
    model.showFeedback = { [weak self] in
      self?.desktop.chat.orderOut(nil)
      self?.openMain()
    }
    model.showReminder = { [weak self] in
      guard let self else { return }
      self.desktop.show()
      if !self.desktop.chat.isVisible { self.desktop.toggleChat() }
      else { self.desktop.chat.orderFrontRegardless() }
    }
    model.refreshPet = { [weak self] in
      guard let self else { return }
      self.desktop.sprite.loadCharacterAssets()
      self.desktop.resize()
      self.mainWindow.title = "\(self.model.companionName) · \(self.model.userName)的一天"
      self.status.button?.title = "☾ \(self.model.companionName)"
    }
    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    status.button?.title = "☾ \(model.companionName)"
    let menu = NSMenu()
    for (title, action) in [
      ("打开主窗口", #selector(openMain)), ("显示桌面伙伴", #selector(showPet)), ("退出", #selector(quit)),
    ] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      menu.addItem(item)
    }
    status.menu = menu
    openMain()
    model.animate("waving")
  }
  @objc func openChatWindow() {
    NSApp.activate(ignoringOtherApps: true)
    desktop.openChat()
  }
  func installMenus() {
    let bar = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(
      withTitle: "关于陪伴者", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: "")
    let chatItem = NSMenuItem(title: "打开聊天窗口", action: #selector(openChatWindow), keyEquivalent: "l")
    chatItem.target = self
    appMenu.addItem(chatItem)
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "隐藏陪伴者", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(
      withTitle: "退出陪伴者", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let reveal = NSMenuItem(title: "显示桌面陪伴者", action: #selector(showPet), keyEquivalent: "d")
    reveal.target = self
    appMenu.addItem(reveal)
    appItem.submenu = appMenu
    bar.addItem(appItem)
    let editItem = NSMenuItem()
    let edit = NSMenu(title: "编辑")
    for (name, selector, key) in [
      ("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"),
      ("全选", "selectAll:", "a"),
    ] { edit.addItem(withTitle: name, action: NSSelectorFromString(selector), keyEquivalent: key) }
    editItem.submenu = edit
    bar.addItem(editItem)
    NSApp.mainMenu = bar
  }
  @objc func openMain() {
    mainWindow.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc func showPet() {
    desktop.show()
    desktop.pet.makeKeyAndOrderFront(nil)
  }
  @objc func quit() { NSApp.terminate(nil) }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    model.pauseForSleep()
    model.save()
    return .terminateNow
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    openMain()
    return true
  }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) { completionHandler([.banner, .sound]) }
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    Task { @MainActor in
      self.openMain()
      if self.model.state.timer?.awaitingReflection == true { self.model.endCurrent() }
      completionHandler()
    }
  }
}
