import SwiftUI

/// 插件：把「广告拦截 / 页面增强 / 工具」等能力统一成可在市场中安装、启用的单元。
/// 元数据与载荷（规则 JSON / 脚本）来自内置目录（`Plugin.catalog`，代码内定义）；
/// 仅「安装/启用」状态会持久化（见 PluginStore），以便日后扩展目录而不丢用户选择。
struct Plugin: Identifiable, Hashable {
    let id: String
    let name: String
    let author: String
    let summary: String
    let detail: String
    let symbol: String
    let tint: UInt
    let category: Category
    let kind: Kind
    let version: String
    var installed: Bool = false
    var enabled: Bool = false

    var color: Color { Color(hex: tint) }

    enum Category: String, CaseIterable, Identifiable {
        case adblock = "广告拦截"
        case enhance = "页面增强"
        case tool = "实用工具"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .adblock: return "shield.lefthalf.filled"
            case .enhance: return "wand.and.stars"
            case .tool: return "wrench.and.screwdriver"
            }
        }
    }

    /// 插件载荷：内容拦截规则（WKContentRuleList JSON）或用户脚本。
    enum Kind: Hashable {
        case contentRule(json: String)
        case userScript(code: String, match: String, atEnd: Bool)
    }
}

/// 持久化的安装/启用状态（按插件 id）。
struct PluginState: Codable { var installed: Bool; var enabled: Bool }

// MARK: - 内置市场目录
extension Plugin {
    static let catalog: [Plugin] = [
        Plugin(
            id: "adblock.basic",
            name: "广告拦截基础版",
            author: "MiniBrowser",
            summary: "拦截常见广告与追踪域名，并隐藏页面广告位",
            detail: "基于 WKContentRuleList 的内容拦截：屏蔽 doubleclick、googlesyndication、google-analytics 等常见广告/追踪请求，并对常见广告容器做 CSS 隐藏。纯本地规则，不上传任何浏览数据。",
            symbol: "shield.lefthalf.filled",
            tint: 0x34C759,
            category: .adblock,
            kind: .contentRule(json: adblockRuleJSON),
            version: "1.0",
            installed: true, enabled: true   // 默认随包安装启用，开箱即用
        ),
        Plugin(
            id: "enhance.cleanfloat",
            name: "清理悬浮广告（示例）",
            author: "社区",
            summary: "隐藏页面常见的悬浮/弹层广告元素",
            detail: "示例增强脚本：在页面加载完成后隐藏 class/id 含 float、popup、modal-ad 的元素。仅作框架演示，匹配所有网站。",
            symbol: "rectangle.on.rectangle.slash",
            tint: 0x5856D6,
            category: .enhance,
            kind: .userScript(
                code: "document.querySelectorAll('[class*=float],[class*=popup],[id*=modal-ad]').forEach(function(e){e.style.display='none'});",
                match: "*://*/*", atEnd: true),
            version: "1.0"
        ),
        Plugin(
            id: "tool.copyhost",
            name: "控制台打印站点（示例）",
            author: "社区",
            summary: "在控制台输出当前站点信息，便于调试",
            detail: "示例工具脚本：页面加载后在控制台打印 host。用于演示工具类插件。",
            symbol: "terminal",
            tint: 0xFF9500,
            category: .tool,
            kind: .userScript(
                code: "console.log('[plugin] 当前站点:', location.host);",
                match: "*://*/*", atEnd: true),
            version: "1.0"
        ),
    ]

    /// 广告拦截规则（WKContentRuleList JSON）：屏蔽常见广告/追踪域名 + 隐藏广告容器。
    /// 注意：WKContentRuleList 仅支持受限正则子集（不支持交替组等），规则保持简单。
    private static let adblockRuleJSON = """
    [
      {"trigger":{"url-filter":"doubleclick\\\\.net"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"googlesyndication\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"google-analytics\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"googletagmanager\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"adservice\\\\.google\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"adnxs\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":"scorecardresearch\\\\.com"},"action":{"type":"block"}},
      {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".ad, .ads, .advert, .adsbox, [id^=ad-], [class*=banner-ad]"}}
    ]
    """
}
