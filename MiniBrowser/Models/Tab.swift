import SwiftUI

/// 标签页（引用类型）：每个标签拥有独立的 WebEngine，保留各自的页面与前进/后退历史。
@MainActor
final class Tab: ObservableObject, Identifiable {
    let id = UUID()
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
    /// 加载前用于缩略图/卡片展示的占位信息
    @Published var placeholderTitle: String
    @Published var placeholderURL: String
    let tint: Color
    /// 引擎是否已发起过加载
    private(set) var didLoad = false

    init(isHome: Bool = true,
         isIncognito: Bool = false,
         placeholderTitle: String = "新标签页",
         placeholderURL: String = "",
         tint: Color = Theme.Colors.accent) {
        self.isHome = isHome
        self.isIncognito = isIncognito
        self.placeholderTitle = placeholderTitle
        self.placeholderURL = placeholderURL
        self.tint = tint
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

    /// 切回该标签时，若有占位地址但尚未加载，则补加载
    func activateIfNeeded(searchTemplate: String) {
        guard !isHome, !didLoad, !placeholderURL.isEmpty else { return }
        didLoad = true
        engine.submit(placeholderURL, searchTemplate: searchTemplate)
    }
}
