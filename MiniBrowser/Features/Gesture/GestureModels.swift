import SwiftUI

// MARK: - 方向（8 向 + 圆形）
enum GestureDirection: String, Codable, CaseIterable, Hashable {
    case up, down, left, right, upLeft, upRight, downLeft, downRight
    /// 圆形手势（顺时针 / 逆时针），由转角和识别，不由 `from(dx:dy:)` 产生。
    case circleClockwise, circleCounterClockwise

    /// 8 个线性方向（不含圆形）：用于手动追加方向的宫格。
    static let linearCases: [GestureDirection] = [.up, .down, .left, .right, .upLeft, .upRight, .downLeft, .downRight]

    var glyph: String {
        switch self {
        case .up: return "↑"; case .down: return "↓"; case .left: return "←"; case .right: return "→"
        case .upLeft: return "↖"; case .upRight: return "↗"; case .downLeft: return "↙"; case .downRight: return "↘"
        case .circleClockwise: return "↻"; case .circleCounterClockwise: return "↺"
        }
    }

    /// 由位移向量映射到最近的 8 向（屏幕坐标：x 向右、y 向下）
    static func from(dx: CGFloat, dy: CGFloat) -> GestureDirection {
        let deg = atan2(dy, dx) * 180 / .pi          // -180...180
        let n = ((Int((deg / 45).rounded()) % 8) + 8) % 8
        switch n {
        case 0: return .right
        case 1: return .downRight
        case 2: return .down
        case 3: return .downLeft
        case 4: return .left
        case 5: return .upLeft
        case 6: return .up
        default: return .upRight
        }
    }
}

extension Array where Element == GestureDirection {
    var glyphs: String { map(\.glyph).joined() }
}

// MARK: - 功能
enum GestureAction: String, Codable, CaseIterable, Identifiable {
    case back, forward, reload, newTab, closeTab, home, tabs, menu, search
    case bookmarks, history, downloads, files, settings
    case toggleNight, toggleIncognito, translate, reading, imageMode, qrScan
    case addBookmark, copyURL, scrollTop, scrollBottom
    case screenshot, nextTab, prevTab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .back: return "后退";            case .forward: return "前进"
        case .reload: return "刷新";          case .newTab: return "新建标签页"
        case .closeTab: return "关闭标签页";  case .home: return "返回主页"
        case .tabs: return "标签页管理";      case .menu: return "打开菜单"
        case .search: return "搜索"
        case .bookmarks: return "书签";       case .history: return "历史"
        case .downloads: return "下载";       case .files: return "文件"
        case .settings: return "设置";        case .toggleNight: return "夜间模式"
        case .toggleIncognito: return "无痕模式"; case .translate: return "网页翻译"
        case .reading: return "阅读模式";     case .imageMode: return "看图模式"
        case .qrScan: return "扫一扫";        case .addBookmark: return "收藏页面"
        case .copyURL: return "复制网址";     case .scrollTop: return "回到顶部"
        case .scrollBottom: return "滚到底部"
        case .screenshot: return "网页截图";  case .nextTab: return "下一个标签"
        case .prevTab: return "上一个标签"
        }
    }

    var symbol: String {
        switch self {
        case .back: return "chevron.left";    case .forward: return "chevron.right"
        case .reload: return "arrow.clockwise"; case .newTab: return "plus.square"
        case .closeTab: return "xmark.square"; case .home: return "house"
        case .tabs: return "square.on.square"; case .menu: return "line.3.horizontal"
        case .search: return "magnifyingglass"
        case .bookmarks: return "bookmark";   case .history: return "clock.arrow.circlepath"
        case .downloads: return "arrow.down.circle"; case .files: return "folder"
        case .settings: return "gearshape";   case .toggleNight: return "moon"
        case .toggleIncognito: return "eyeglasses"; case .translate: return "character.bubble"
        case .reading: return "doc.text";     case .imageMode: return "photo.stack"
        case .qrScan: return "qrcode.viewfinder"; case .addBookmark: return "bookmark.fill"
        case .copyURL: return "doc.on.doc";   case .scrollTop: return "arrow.up.to.line"
        case .scrollBottom: return "arrow.down.to.line"
        case .screenshot: return "camera.viewfinder"; case .nextTab: return "arrow.right.square"
        case .prevTab: return "arrow.left.square"
        }
    }
}

// MARK: - 规则
struct GestureRule: Identifiable, Codable, Hashable {
    var id = UUID()
    var directions: [GestureDirection]
    var action: GestureAction
    var enabled: Bool = true

    static let defaults: [GestureRule] = [
        .init(directions: [.left], action: .back),
        .init(directions: [.right], action: .forward),
        .init(directions: [.up], action: .newTab),
        .init(directions: [.down], action: .closeTab),
        .init(directions: [.up, .down], action: .reload),
        .init(directions: [.up, .right], action: .tabs),
        .init(directions: [.up, .left], action: .menu),
        .init(directions: [.down, .up], action: .scrollTop),
        .init(directions: [.circleClockwise], action: .reload),
    ]
}

// MARK: - 放置方式
enum GesturePlacement: String, Codable, CaseIterable, Identifiable {
    case floating = "悬浮按钮"
    case toolbar = "工具栏图标"
    var id: String { rawValue }
}

// MARK: - 配置（含按钮启用、位置、直线容差等，整体持久化）
struct GestureConfig: Codable {
    var enabled: Bool = true
    /// 归一化位置 0...1（仅悬浮模式）
    var posX: Double = 0.93
    var posY: Double = 0.80
    var rules: [GestureRule] = GestureRule.defaults
    /// 放置方式：悬浮 / 底部居中。
    var placement: GesturePlacement = .floating
    /// 直线容差 0(精确,易分段)…1(宽松,弯曲也当直线)：越大，画得弯的线越容易被当成一段直线。
    var straightness: Double = 0.5
    /// 按钮大小倍率 0.8…1.4。
    var buttonSize: Double = 1.0
    /// 是否识别圆形手势。
    var enableCircle: Bool = true
    /// 命中时是否触觉反馈。
    var haptics: Bool = true
    /// 工具栏模式下手势图标是否醒目显示（强调色+细环）；false 则与普通图标一致，防止分心。
    var distinctIcon: Bool = true

    /// 直线容差角（度）：相邻段方向偏离当前直线段在此角度内不算转向。
    /// 上限必须 < 45°，否则相邻的 8 向（如 ← 与 ↙）会被并成同一段——导致「左都识别成左下」。
    var straightnessToleranceDeg: Double { 12 + straightness * 28 }   // 12°…40°

    init() {}
    /// 容错解码：旧配置缺新字段时用默认值，避免整份配置丢失。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled      = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        posX         = try c.decodeIfPresent(Double.self, forKey: .posX) ?? 0.93
        posY         = try c.decodeIfPresent(Double.self, forKey: .posY) ?? 0.80
        rules        = try c.decodeIfPresent([GestureRule].self, forKey: .rules) ?? GestureRule.defaults
        placement    = try c.decodeIfPresent(GesturePlacement.self, forKey: .placement) ?? .floating
        straightness = try c.decodeIfPresent(Double.self, forKey: .straightness) ?? 0.5
        buttonSize   = try c.decodeIfPresent(Double.self, forKey: .buttonSize) ?? 1.0
        enableCircle = try c.decodeIfPresent(Bool.self, forKey: .enableCircle) ?? true
        haptics      = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? true
        distinctIcon = try c.decodeIfPresent(Bool.self, forKey: .distinctIcon) ?? true
    }
}

// MARK: - 识别器：路径点 → 方向序列（或圆形）
enum GestureRecognizer {
    /// segment：判定一段方向所需的最小位移。
    /// toleranceDeg：直线容差角——线偏离当前直线段在此角度内不算转向（弯一点也当直线）。
    /// detectCircle：是否优先识别圆形。
    static func recognize(_ points: [CGPoint], segment: CGFloat = 22,
                          toleranceDeg: Double = 30, detectCircle: Bool = true) -> [GestureDirection] {
        guard points.count > 1 else { return [] }
        if detectCircle, let circle = circle(points) { return [circle] }
        var result: [GestureDirection] = []
        var anchor = points[0]
        var runAngle: Double? = nil   // 当前直线段的参考角（度）
        for p in points.dropFirst() {
            let dx = p.x - anchor.x, dy = p.y - anchor.y
            if hypot(dx, dy) < segment { continue }
            let angle = atan2(dy, dx) * 180 / .pi
            // 关键：每形成一小段就推进 anchor，方向按「最近这一小段」判定（短基线）。
            // 否则用远锚点测角，转弯后「远锚点→当前点」会是对角线混合——
            // 导致「左→下」被读成「左下」，且「下」要拉很长才够纵向分量。
            anchor = p
            // 仍在当前直线段容差内：视作同一方向的延续（吸收轻微抖动），不新增方向。
            if let ra = runAngle, abs(angleDelta(angle, ra)) <= toleranceDeg { continue }
            let dir = GestureDirection.from(dx: dx, dy: dy)
            if result.last != dir { result.append(dir) }
            runAngle = angle
        }
        return result
    }

    /// 两角之差，归一化到 -180…180。
    private static func angleDelta(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > 180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }

    /// 圆形识别：累计相邻线段的有符号转角，总转角接近 ±360° 即判为圆。
    /// 屏幕坐标 y 向下，转角和 > 0 视觉为顺时针。
    static func circle(_ points: [CGPoint], minTurnDegrees: CGFloat = 300) -> GestureDirection? {
        guard points.count >= 10 else { return nil }
        var totalTurn: CGFloat = 0
        for i in 1..<(points.count - 1) {
            let a = points[i - 1], b = points[i], c = points[i + 1]
            let v1 = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let v2 = CGPoint(x: c.x - b.x, y: c.y - b.y)
            guard hypot(v1.x, v1.y) > 1, hypot(v2.x, v2.y) > 1 else { continue }
            let cross = v1.x * v2.y - v1.y * v2.x
            let dot = v1.x * v2.x + v1.y * v2.y
            totalTurn += atan2(cross, dot)
        }
        guard abs(totalTurn) * 180 / .pi >= minTurnDegrees else { return nil }
        return totalTurn > 0 ? .circleClockwise : .circleCounterClockwise
    }
}
