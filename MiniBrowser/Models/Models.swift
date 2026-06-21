import SwiftUI

// MARK: - 快捷网站
struct QuickLink: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var url: String
    /// 站点图标显示用的短字（无品牌资产时退化为首字 / 字母）
    var glyph: String
    var colorHex: UInt
    /// 可选 SF Symbol（部分内置入口用图标而非文字）
    var symbol: String? = nil
    var color: Color { Color(hex: colorHex) }
}

// MARK: - 搜索引擎
struct SearchEngine: Identifiable, Hashable, Codable {
    var name: String
    /// 查询模板：含 `%s` 则替换为关键词，否则把编码后的关键词追加到末尾（如 `.../search?q=`）。
    var template: String
    var glyph: String
    var colorHex: UInt
    var id: String { name }
    var color: Color { Color(hex: colorHex) }

    static let builtIn: [SearchEngine] = [
        .init(name: "Bing", template: "https://www.bing.com/search?q=", glyph: "b", colorHex: 0x008373),
        .init(name: "Google", template: "https://www.google.com/search?q=", glyph: "G", colorHex: 0x4285F4),
        .init(name: "百度", template: "https://www.baidu.com/s?wd=", glyph: "百", colorHex: 0x2932E1),
        .init(name: "搜狗", template: "https://www.sogou.com/web?query=", glyph: "搜", colorHex: 0xFB6022),
        .init(name: "360搜索", template: "https://www.so.com/s?q=", glyph: "3", colorHex: 0x10B266),
        .init(name: "DuckDuckGo", template: "https://duckduckgo.com/?q=", glyph: "D", colorHex: 0xDE5833),
    ]
}

// MARK: - 书签
struct Bookmark: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var url: String
    var glyph: String
    var colorHex: UInt
    var isFolder: Bool = false
    /// 所属文件夹 id（nil = 根目录）。文件夹本身也用此字段表达层级。
    var parentID: UUID? = nil
    var color: Color { Color(hex: colorHex) }
}

// MARK: - 历史
struct HistoryItem: Identifiable, Hashable, Codable {
    var id = UUID()
    var title: String
    var url: String
    var time: String
    var glyph: String
    var colorHex: UInt
    /// 记录当日的日期键（yyyy-MM-dd），用于按真实日期分组（今天/昨天/更早）。
    /// 可选以兼容旧持久化数据（无此字段的老条目归入「更早」）。
    var day: String? = nil
    var color: Color { Color(hex: colorHex) }
}

struct HistorySection: Identifiable, Codable {
    var id = UUID()
    var title: String          // 今天 / 昨天 / 更早
    var items: [HistoryItem]
}

// MARK: - 下载 / 文件
enum FileKind: String, CaseIterable {
    case download = "下载"
    case document = "文档"
    case video = "视频"
    case image = "图片"
    case audio = "音频"
    case archive = "压缩包"
    case ebook = "电子书"
    case recent = "最近使用"

    var symbol: String {
        switch self {
        case .download: return "arrow.down.circle.fill"
        case .document: return "doc.fill"
        case .video: return "play.rectangle.fill"
        case .image: return "photo.fill"
        case .audio: return "music.note"
        case .archive: return "doc.zipper"
        case .ebook: return "book.fill"
        case .recent: return "clock.fill"
        }
    }

    var color: Color {
        switch self {
        case .download: return Theme.Colors.accent
        case .document: return Color(hex: 0x5AC8FA)
        case .video: return Color(hex: 0xFF375F)
        case .image: return Color(hex: 0x34C759)
        case .audio: return Color(hex: 0xFF9F0A)
        case .archive: return Color(hex: 0xAF52DE)
        case .ebook: return Color(hex: 0xFF9500)
        case .recent: return Color(hex: 0x8E8E93)
        }
    }
}

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var size: String
    var modified: String
    var symbol: String
    var color: Color
    var isFolder: Bool = false
}

// MARK: - 菜单项
struct MenuAction: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var symbol: String
    var tint: Color = Theme.Colors.primaryText
    /// 标记开关型功能（夜间、无图、无痕等）
    var isToggle: Bool = false
}
