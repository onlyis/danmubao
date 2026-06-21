import SwiftUI

/// 标签页（引用类型）：每个标签拥有独立的 WebEngine，保留各自的页面与前进/后退历史。
@MainActor
final class Tab: ObservableObject, Identifiable {
    let id: UUID
    let isIncognito: Bool

    /// 引擎惰性创建：启动/标签网格里不会为未访问的标签建出 WKWebView。
    private var _engine: WebEngine?
    /// 引擎被 LRU 池回收后保存的会话状态，下次访问 engine 时无损恢复（含前进/后退列表）。
    private var savedSession: Data?
    var engine: WebEngine {
        if let e = _engine { return e }
        let e = WebEngine()
        if let s = savedSession { e.sessionState = s; savedSession = nil }
        _engine = e
        return e
    }
    var hasEngine: Bool { _engine != nil }

    /// 回收后台引擎以释放 WKWebView（海量标签时由 EnginePool 调用）。
    /// 先把会话状态与最新标题/地址存下来，再丢弃引擎；卡片仍能正确展示，重新激活时无损恢复。
    func evictEngine() {
        guard let e = _engine else { return }
        if !e.title.isEmpty { placeholderTitle = e.title }
        if !e.displayURL.isEmpty { placeholderURL = e.displayURL }
        savedSession = e.sessionState
        _engine = nil
    }

    @Published var isHome: Bool
    /// 标签卡片的真实页面缩略图（离开/打开标签管理时截取）
    @Published var thumbnail: UIImage?
    /// 加载前用于缩略图/卡片展示的占位信息
    @Published var placeholderTitle: String
    @Published var placeholderURL: String
    /// 卡片配色（以 hex 存储，便于持久化；Color 不可 Codable）
    let tintHex: UInt
    var tint: Color { Color(hex: tintHex) }
    /// 引擎是否已发起过加载
    private(set) var didLoad = false

    init(id: UUID = UUID(),
         isHome: Bool = true,
         isIncognito: Bool = false,
         placeholderTitle: String = "新标签页",
         placeholderURL: String = "",
         tintHex: UInt = 0x0A84FF) {
        self.id = id
        self.isHome = isHome
        self.isIncognito = isIncognito
        self.placeholderTitle = placeholderTitle
        self.placeholderURL = placeholderURL
        self.tintHex = tintHex
    }

    /// 用于持久化的轻量快照（不含会话/引擎，海量标签下体积可控）。
    var snapshot: TabSnapshot {
        TabSnapshot(id: id, isHome: isHome, title: displayTitle, url: displayURL, tintHex: tintHex)
    }

    /// 从快照恢复（非无痕标签）。didLoad 为 false，选中时再惰性加载，启动不建引擎。
    convenience init(_ s: TabSnapshot) {
        self.init(id: s.id, isHome: s.isHome, isIncognito: false,
                  placeholderTitle: s.title, placeholderURL: s.url, tintHex: s.tintHex)
    }

    var displayTitle: String {
        if hasEngine, !engine.title.isEmpty { return engine.title }
        return placeholderTitle
    }
    var displayURL: String {
        if hasEngine, !engine.displayURL.isEmpty { return engine.displayURL }
        return placeholderURL
    }

    /// 加载某地址（首次访问或地址栏输入）
    func load(_ text: String, searchTemplate: String) {
        isHome = false
        placeholderTitle = text
        placeholderURL = text
        didLoad = true
        engine.submit(text, searchTemplate: searchTemplate)
    }

    /// 截取当前页缩略图（仅当前可见标签可靠，需引擎已创建）
    func captureThumbnail() {
        guard let e = _engine, !isHome else { return }
        e.snapshot { [weak self] img in if let img { self?.thumbnail = img } }
    }

    /// 切回该标签时，若有占位地址但尚未加载，则补加载
    func activateIfNeeded(searchTemplate: String) {
        guard !isHome, !didLoad, !placeholderURL.isEmpty else { return }
        didLoad = true
        engine.submit(placeholderURL, searchTemplate: searchTemplate)
    }
}

/// 标签持久化快照：仅存元信息（地址/标题/配色），不含会话状态——
/// 海量标签时体积可控（每条约百字节）。恢复后选中再惰性加载。
struct TabSnapshot: Codable {
    var id: UUID
    var isHome: Bool
    var title: String
    var url: String
    var tintHex: UInt
}

/// 持久化的标签集合（普通标签 + 当前选中 id；无痕标签不持久化）。
struct TabsState: Codable {
    var tabs: [TabSnapshot]
    var currentID: UUID?
}
