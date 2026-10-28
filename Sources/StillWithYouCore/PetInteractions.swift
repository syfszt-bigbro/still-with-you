import Foundation

public enum PetReaction: String, CaseIterable, Sendable {
  case nearbyAbove, nearbyBelow, nearbyLeft, nearbyRight
  case dizzy, fastDrag, repeatedDrag, top, bottom, corner, left, right, center, screenChange, longDrag, hover, reach
  public var lines: [String] {
    switch self {
    case .nearbyAbove: return ["我脖子都举酸老，下来点嘛。", "你在上头看啥子哦，我都望你好几秒了。", "莫举那么高嘛，我抬头抬累了。"]
    case .nearbyBelow: return ["你在下面找啥子嘛？我都低头看半天了。", "往上挪一点嘛，我低头低得脖子酸。", "躲到底下去嗦？我看到你了。"]
    case .nearbyLeft: return ["你在左边站那么远，我手都够不到。", "往我这边来一点嘛，莫在左边看热闹。", "左边那个，喊你过来摆两句。"]
    case .nearbyRight: return ["你在右边站那么远，我摸不到你哦。", "右边有啥子好看的嘛，过来点。", "莫站那么远，往这边挪一点嘛。"]
    case .dizzy: return ["你把我绕晕了，先停一小会儿。", "别转啦，我的目光都打结了。", "这是鼠标，还是你的小风车呀？"]
    case .fastDrag: return ["慢一点嘛，我都快跟不上了。", "等一下，我的小短腿要冒烟了。", "你这是搬家，还是带我起飞呀？"]
    case .repeatedDrag: return ["怎么又搬家呀，让我歇一会儿嘛。", "新地址还没记住，又换地方啦？", "你在给我挑风水宝地吗？"]
    case .top: return ["好，现在轮到我俯视你了。", "这里视野不错，我先占个高处。", "站这么高，今天我来当瞭望员。"]
    case .bottom: return ["把我放这么低，是要我仰视你吗？", "好吧，我就在底下给你托个底。", "楼下住户已就位，有事往下看。"]
    case .corner: return ["这个角落归我了，正好安个小窝。", "让我靠边待着呀？行，我偷偷看热闹。", "角落也不错，安静得适合做梦。"]
    case .left: return ["左边这块地，我先替你守着。", "今天安排我当左护法呀？", "往左看，我在这儿呢。"]
    case .right: return ["右边也挺好，我就在旁边陪你。", "右护法到岗，不收站岗费。", "我靠右站，给你的大计划让点地方。"]
    case .center: return ["怎么把我摆正中间啦，今天我是主角？", "这个位置有点显眼，我先站稳。", "站在这里，是不是挡住你的灵感啦？"]
    case .screenChange: return ["咦，换一块屏幕，就当出门旅行了。", "新地方到了，我先认认路。", "跨屏搬家完成，行李只有我自己。"]
    case .longDrag: return ["带我逛这么久，终于选好位置啦？", "这趟桌面旅行有点长，让我歇歇脚。", "终点到了吧？我想在这儿坐一会儿。"]
    case .reach: return ["让我轻轻碰一下，抓到你的小鼠标啦。", "停得这么近，那我伸手打个招呼。", "碰一下就放你走，不耽误你忙。"]
    case .hover: return ["鼠标停在这儿，是有话想说吗？", "我看见你啦，想聊就点点我。", "你不说话，那我们就安静待一会儿。"]
    }
  }
  public var scene: String {
    switch self {
    case .nearbyAbove: return "鼠标在人物上方远于触手的区域停留数秒，调侃抬头脖子酸"
    case .nearbyBelow: return "鼠标在人物下方停留数秒，调侃低头看用户"
    case .nearbyLeft: return "鼠标在人物左侧、手够不到的区域停留数秒，邀请靠近"
    case .nearbyRight: return "鼠标在人物右侧、手够不到的区域停留数秒，邀请靠近"
    case .dizzy: return "鼠标绕着人物转圈，俏皮抱怨被绕晕"
    case .fastDrag: return "被快速拖动，轻轻抱怨跟不上"
    case .repeatedDrag: return "被反复搬动，调侃频繁搬家"
    case .top: return "被放在屏幕上方，调侃开始俯视用户"
    case .bottom: return "被放在屏幕下方，调侃要仰视用户"
    case .corner: return "被放在屏幕角落，调侃安家或躲清静"
    case .left: return "被放在屏幕左边，调侃左护法"
    case .right: return "被放在屏幕右边，调侃右护法"
    case .center: return "被放在屏幕正中央，调侃站在舞台中间"
    case .screenChange: return "被移到另一块显示器，调侃跨屏旅行"
    case .longDrag: return "被拖动逛了很久才放下，调侃桌面旅行"
    case .reach: return "鼠标停在手边，人物伸手轻碰它，用一句短话打招呼，不声称控制鼠标"
    case .hover: return "鼠标安静停在人物附近，温柔问是不是想聊天，不推断用户情绪"
    }
  }
}

/// Uses monotonic seconds. No input history is persisted.
public struct PetInteractions {
  private var angle: Double?
  private var pointerTime: Double?
  private var turns: [(Double, Double)] = []
  private var dragPoint: (Double, Double, Double)?
  private var dragDistance = 0.0
  private var dragStarted = 0.0
  private var countedDrag = false
  private var dragStarts: [Double] = []
  private var hoverAnchor: (Double, Double, Double)?
  private var hoverSpoken = false
  private var reachAnchor: (Double, Double, Double)?
  private var reachTime: Double?
  private var reached = false
  private var nearbyRegion: PetReaction?
  private var nearbySince: Double?
  private var nearbyTime: Double?
  private var greetedNearby = false
  private var lastReaction = -Double.infinity
  private var reactionTimes: [PetReaction: Double] = [:]
  private var shakePoint: (Double, Double)?
  private var shakeVector: (Double, Double)?
  private var reversals: [Double] = []
  public init() {}

  public mutating func resetPointer() { angle = nil; pointerTime = nil; turns = []; hoverAnchor = nil; hoverSpoken = false; shakePoint = nil; shakeVector = nil; reversals = [] }
  private mutating func emit(_ reaction: PetReaction, at now: Double, placement: Bool = false) -> PetReaction? {
    guard (placement || now - lastReaction >= 2), now - (reactionTimes[reaction] ?? -.infinity) >= 15 else { return nil }
    lastReaction = now
    reactionTimes[reaction] = now
    if reaction == .dizzy { turns = [] }; dragStarts = []
    return reaction
  }
  public mutating func resetReach() { reachAnchor = nil; reachTime = nil; reached = false }
  /// x/y are source-cell pixels relative to the reachable fingertip, not screen coordinates.
  public mutating func reach(x: Double, y: Double, at now: Double) -> PetReaction? {
    guard hypot(x, y) <= 28 else { resetReach(); return nil }
    if let last = reachTime, now - last >= 0.3 || now < last { resetReach() }
    reachTime = now
    if let anchor = reachAnchor, hypot(x - anchor.0, y - anchor.1) <= 8 {
      if now - anchor.2 >= 1.2 && !reached {
        if let event = emit(.reach, at: now) { reached = true; return event }
      }
    } else { reachAnchor = (x, y, now) }
    return nil
  }
  /// Coordinates relative to the sprite center in source pixels. No precision aiming required.
  public mutating func proximity(x: Double, y: Double, at now: Double) -> PetReaction? {
    let region: PetReaction?
    if hypot(x / 125, y / 145) <= 1 { region = .reach }
    else if abs(x) <= 130 && y >= 165 && y <= 260 { region = .nearbyAbove }
    else if abs(x) <= 130 && y <= -165 && y >= -260 { region = .nearbyBelow }
    else if x <= -150 && x >= -270 && abs(y) <= 160 { region = .nearbyLeft }
    else if x >= 150 && x <= 270 && abs(y) <= 160 { region = .nearbyRight }
    else { region = nil }
    guard let region else {
      nearbySince = nil; nearbyTime = nil; greetedNearby = false; nearbyRegion = nil; return nil
    }
    if nearbyRegion != region || nearbyTime.map({ now - $0 > 0.4 || now < $0 }) == true {
      nearbySince = nil; greetedNearby = false
    }
    nearbyRegion = region; nearbyTime = now
    if nearbySince == nil { nearbySince = now }
    let dwell = region == .reach ? 0.6 : 4.0
    if !greetedNearby, now - (nearbySince ?? now) >= dwell, let event = emit(region, at: now) {
      greetedNearby = true; return event
    }
    return nil
  }
  public mutating func pointer(x: Double, y: Double, at now: Double, includeHover: Bool = true) -> PetReaction? {
    if let time = pointerTime, now - time >= 0.6 || now < time { resetPointer() }
    let radius = hypot(x, y)
    guard radius > 12 && radius < 550 else { resetPointer(); return nil }
    if let point = shakePoint {
      let dx = x - point.0, dy = y - point.1
      if hypot(dx, dy) >= 16 {
        if let vector = shakeVector, dx * vector.0 + dy * vector.1 < -0.4 * hypot(dx, dy) * hypot(vector.0, vector.1) {
          reversals.append(now)
        }
        shakeVector = (dx, dy); shakePoint = (x, y)
      }
    } else { shakePoint = (x, y) }
    reversals.removeAll { now - $0 > 2 }
    if reversals.count >= 4, let event = emit(.dizzy, at: now) {
      reversals = []; pointerTime = now; return event
    }
    if includeHover && radius < 220 {
      if let anchor = hoverAnchor, hypot(x - anchor.0, y - anchor.1) < 12 {
        if now - anchor.2 >= 4 && !hoverSpoken {
          if let event = emit(.hover, at: now) { hoverSpoken = true; pointerTime = now; return event }
        }
      } else { hoverAnchor = (x, y, now) }
    } else { hoverAnchor = nil; hoverSpoken = false }
    let next = atan2(y, x)
    defer { angle = next; pointerTime = now }
    guard let before = angle, let time = pointerTime, now > time, now - time < 0.6 else {
      turns = []; return nil
    }
    var delta = next - before
    if delta > .pi { delta -= 2 * .pi }
    if delta < -.pi { delta += 2 * .pi }
    guard abs(delta) < .pi * 0.85 else { turns = []; return nil }
    turns.append((now, delta))
    turns.removeAll { now - $0.0 > 12 }
    // Signed rotation avoids mistaking back-and-forth head movements for circles.
    if abs(turns.reduce(0) { $0 + $1.1 }) >= 4 * .pi {
      return emit(.dizzy, at: now)
    }
    return nil
  }
  public mutating func beginDrag(x: Double, y: Double, at now: Double) {
    resetPointer(); resetReach()
    dragPoint = (x, y, now); dragStarted = now; dragDistance = 0; countedDrag = false
  }
  public mutating func drag(x: Double, y: Double, at now: Double) -> PetReaction? {
    guard let before = dragPoint else { return nil }
    dragPoint = (x, y, now)
    let delta = now - before.2
    guard delta > 0, delta < 0.5 else { dragDistance = 0; dragStarted = now; return nil }
    dragDistance += hypot(x - before.0, y - before.1)
    if !countedDrag && dragDistance > 8 {
      countedDrag = true
      dragStarts.removeAll { now - $0 > 12 }
      dragStarts.append(now)
      if dragStarts.count >= 4 { return emit(.repeatedDrag, at: now) }
    }
    let elapsed = now - dragStarted
    if elapsed >= 0.12 && dragDistance >= 180 && dragDistance / elapsed > 1200 {
      return emit(.fastDrag, at: now)
    }
    return nil
  }
  /// Coordinates are normalized over the usable movement range (bottom = 0, top = 1).
  public mutating func drop(x: Double, y: Double, crossedScreen: Bool, at now: Double) -> PetReaction? {
    guard countedDrag else { return nil }
    let event: PetReaction?
    if crossedScreen { event = .screenChange }
    else if now - dragStarted >= 5 && dragDistance >= 500 { event = .longDrag }
    else if (x < 0.12 || x > 0.88) && (y < 0.12 || y > 0.88) { event = .corner }
    else if y > 0.88 { event = .top }
    else if y < 0.12 { event = .bottom }
    else if x < 0.12 { event = .left }
    else if x > 0.88 { event = .right }
    else if abs(x - 0.5) < 0.14 && abs(y - 0.5) < 0.14 { event = .center }
    else { event = nil }
    return event.flatMap { emit($0, at: now, placement: true) }
  }
  public mutating func endDrag() { dragPoint = nil; resetPointer() }
}
