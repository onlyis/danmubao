import SwiftUI

// MARK: - 方向（8 向）
enum GestureDirection: String, Codable, CaseIterable, Hashable {
    case up, down, left, right, upLeft, upRight, downLeft, downRight

    var glyph: String {
        switch self {
        case .up: return "↑"; case .down: return "↓"; case .left: return "←"; case .right: return "→"
        case .upLeft: return "↖"; case .upRight: return "↗"; case .downLeft: return "↙"; case .downRight: return "↘"
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
    case back, forward, reload, newTab, closeTab, home, tabs, menu
    case bookmarks, history, downloads, files, settings
    case toggleNight, toggleIncognito, translate, reading, imageMode, qrScan
    case addBookmark, copyURL, scrollTop, scrollBottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .back: return "后退";            case .forward: return "前进"
        case .reload: return "刷新";          case .newTab: return "新建标签页"
        case .closeTab: return "关闭标签页";  case .home: return "返回主页"
        case .tabs: return "标签页管理";      case .menu: return "打开菜单"
        case .bookmarks: return "书签";       case .history: return "历史"
        case .downloads: return "下载";       case .files: return "文件"
        case .settings: return "设置";        case .toggleNight: return "夜间模式"
        case .toggleIncognito: return "无痕模式"; case .translate: return "网页翻译"
        case .reading: return "阅读模式";     case .imageMode: return "看图模式"
        case .qrScan: return "扫一扫";        case .addBookmark: return "收藏页面"
        case .copyURL: return "复制网址";     case .scrollTop: return "回到顶部"
        case .scrollBottom: return "滚到底部"
        }
    }

    var symbol: String {
        switch self {
        case .back: return "chevron.left";    case .forward: return "chevron.right"
        case .reload: return "arrow.clockwise"; case .newTab: return "plus.square"
        case .closeTab: return "xmark.square"; case .home: return "house"
        case .tabs: return "square.on.square"; case .menu: return "line.3.horizontal"
        case .bookmarks: return "bookmark";   case .history: return "clock.arrow.circlepath"
        case .downloads: return "arrow.down.circle"; case .files: return "folder"
        case .settings: return "gearshape";   case .toggleNight: return "moon"
        case .toggleIncognito: return "eyeglasses"; case .translate: return "character.bubble"
        case .reading: return "doc.text";     case .imageMode: return "photo.stack"
        case .qrScan: return "qrcode.viewfinder"; case .addBookmark: return "bookmark.fill"
        case .copyURL: return "doc.on.doc";   case .scrollTop: return "arrow.up.to.line"
        case .scrollBottom: return "arrow.down.to.line"
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
    ]
}

// MARK: - 配置（含按钮启用与位置，整体持久化）
struct GestureConfig: Codable {
    var enabled: Bool = true
    /// 归一化位置 0...1
    var posX: Double = 0.93
    var posY: Double = 0.80
    var rules: [GestureRule] = GestureRule.defaults
}

// MARK: - 识别器：路径点 → 方向序列
enum GestureRecognizer {
    /// segment：判定一段方向所需的最小位移
    static func recognize(_ points: [CGPoint], segment: CGFloat = 26) -> [GestureDirection] {
        guard points.count > 1 else { return [] }
        var result: [GestureDirection] = []
        var anchor = points[0]
        for p in points.dropFirst() {
            let dx = p.x - anchor.x, dy = p.y - anchor.y
            if hypot(dx, dy) < segment { continue }
            let dir = GestureDirection.from(dx: dx, dy: dy)
            if result.last != dir { result.append(dir) }
            anchor = p
        }
        return result
    }
}
