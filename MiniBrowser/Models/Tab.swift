import SwiftUI

/// 标签页（引用类型）：每个标签拥有独立的 WebEngine，保留各自的页面与前进/后退历史。
@MainActor
final class Tab: ObservableObject, Identifiable {
    let id = UUID()
    let isIncognito: Bool

    /// 引擎惰性创建：启动/标签网格里不会为未访问的标签建出 WKWebView。
    private var _engine: WebEngine?
    var engine: WebEngine {
        if let e = _engine { return e }
        let e = WebEngine()
        _engine = e
        return e
    }
    var hasEngine: Bool { _engine != nil }

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
