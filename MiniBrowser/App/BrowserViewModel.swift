import SwiftUI

/// 全局浏览器状态。本阶段聚焦 UI 与流程，数据均为示例数据。
@MainActor
final class BrowserViewModel: ObservableObject {

    // MARK: - 浏览状态
    /// 当前是否处于网页浏览态（false = 主页 / 新标签页）
    @Published var isBrowsing: Bool = false
    @Published var isIncognito: Bool = false
    @Published var isNightMode: Bool = false
    @Published var isNoImageMode: Bool = false
    @Published var isAdBlockOn: Bool = true
    @Published var isDesktopMode: Bool = false

    // MARK: - 外观
    @Published var appearanceMode: AppearanceMode = .system
    @Published var oledBlack: Bool = false
    @Published var wallpaper: Wallpaper = .none

    enum AppearanceMode: String, CaseIterable, Identifiable {
        case system = "跟随系统", light = "始终浅色", dark = "始终深色"
        var id: String { rawValue }
        var scheme: ColorScheme? { self == .light ? .light : (self == .dark ? .dark : nil) }
    }

    /// 最终强制的配色（无痕/夜间始终深色）
    var resolvedScheme: ColorScheme? {
        if isIncognito || isNightMode { return .dark }
        return appearanceMode.scheme
    }
    /// 默认搜索引擎模板
    var searchTemplate = "https://www.bing.com/search?q="

    /// 当前激活标签的网页引擎
    var engine: WebEngine? { currentTab?.engine }
    /// 当前页面地址 / 标题（用于网站设置、二维码等只读展示）
    var currentURL: String { currentTab?.displayURL ?? "" }
    var currentTitle: String { currentTab?.displayTitle ?? "" }

    // MARK: - 路由（全屏页面）
    enum Route: Identifiable {
        case bookmarks, history, downloads, files, settings
        case reading, imageViewer, comic, toolbox, qrScanner, reader, translate
        case adblock, jsExtensions, devtools, cookies, gestures, plugins
        var id: String { String(describing: self) }
    }
    @Published var route: Route?

    // MARK: - 弹出层
    @Published var showMenu = false
    @Published var showTabs = false
    @Published var showWebsiteSettings = false
    @Published var showSearch = false
    @Published var showVideoFloat = false
    @Published var showDownloadConfirm = false
    @Published var showMarkAds = false
    @Published var showSelectionToolbar = false
    @Published var selectionText = ""

    // MARK: - 轻提示（独立 ToastStore，避免每次提示刷新整个 VM 的观察者）
    let toasts = ToastStore()
    /// 薄转发：保留既有 `vm.showToast(...)` 调用点，实际状态变更落在 ToastStore 上。
    func showToast(_ text: String, symbol: String = "checkmark.circle.fill") {
        toasts.show(text, symbol: symbol)
    }

    // MARK: - 数据
    @Published var quickLinks: [QuickLink] = SampleData.quickLinks
    /// 书签 + 历史拆到独立存储层（见 LibraryStore）
    let library = LibraryStore()

    // MARK: - 标签页（每个标签独立引擎）
    @Published var tabs: [Tab] = SampleData.makeTabs()
    @Published var incognitoTabs: [Tab] = []
    @Published var currentTabID: UUID?

    /// id → Tab 索引，保证海量标签下 currentTab 查找为 O(1)（避免每帧线性扫描）。
    private var tabIndex: [UUID: Tab] = [:]
    /// 活跃引擎 LRU 上限池：海量标签时只保留最近 N 个 WKWebView，其余回收。
    let enginePool = EnginePool()

    /// 手势按钮配置（持久化）
    @Published var gesture = GestureConfig() { didSet { DiskStore.save(gesture, to: "gestures.json") } }

    /// 看图模式：当前页面提取出的图片地址
    @Published var pageImages: [String] = []

    init() {
        if let g = DiskStore.load(GestureConfig.self, from: "gestures.json") { gesture = g }
        for t in tabs { tabIndex[t.id] = t }
        currentTabID = tabs.first?.id
    }

    // MARK: - 手势
    /// 匹配方向序列到启用规则
    func matchGesture(_ directions: [GestureDirection]) -> GestureAction? {
        guard !directions.isEmpty else { return nil }
        return gesture.rules.first { $0.enabled && $0.directions == directions }?.action
    }

    /// 执行手势命中的功能
    func perform(_ action: GestureAction) {
        switch action {
        case .back: back()
        case .forward: forward()
        case .reload: engine?.reload()
        case .newTab: newTab()
        case .closeTab: if let t = currentTab { close(t) }
        case .home: goHome()
        case .tabs: showTabs = true
        case .menu: showMenu = true
        case .bookmarks: route = .bookmarks
        case .history: route = .history
        case .downloads: route = .downloads
        case .files: route = .files
        case .settings: route = .settings
        case .toggleNight: withAnimation { isNightMode.toggle() }
        case .toggleIncognito: toggleIncognito()
        case .translate: route = .translate
        case .reading: route = .reading
        case .imageMode: route = .imageViewer
        case .qrScan: route = .qrScanner
        case .addBookmark: addBookmark(title: currentTitle, url: currentURL); return
        case .copyURL:
            UIPasteboard.general.string = currentURL
            showToast("已复制网址", symbol: "doc.on.doc"); return
        case .scrollTop:
            engine?.webView.evaluateJavaScript("window.scrollTo({top:0,behavior:'smooth'})")
        case .scrollBottom:
            engine?.webView.evaluateJavaScript("window.scrollTo({top:document.body.scrollHeight,behavior:'smooth'})")
        }
        Haptics.soft()
        showToast(action.title, symbol: action.symbol)
    }

    // MARK: - 书签（委托 LibraryStore，附带 Toast 反馈）
    func addBookmark(title: String, url: String) {
        switch library.addBookmark(title: title, url: url) {
        case .added:     showToast("已添加到书签", symbol: "bookmark.fill")
        case .duplicate: showToast("已在书签中", symbol: "bookmark.fill")
        case .empty:     showToast("无可收藏的页面", symbol: "exclamationmark.circle.fill")
        }
    }

    /// 进入看图模式：从当前页面提取真实图片，再打开网格
    func openImageMode() {
        guard isBrowsing, let engine else {
            pageImages = []
            route = .imageViewer
            return
        }
        engine.fetchImageURLs { [weak self] urls in
            self?.pageImages = urls
            self?.route = .imageViewer
        }
    }

    var activeTabs: [Tab] { isIncognito ? incognitoTabs : tabs }
    /// O(1) 查找：先走索引，命中且属当前模式则返回，否则回退到首个标签。
    var currentTab: Tab? {
        if let id = currentTabID, let t = tabIndex[id], t.isIncognito == isIncognito { return t }
        return activeTabs.first
    }
    var tabCount: Int { max(activeTabs.count, 1) }

    // MARK: - 导航动作
    func open(url: String, title: String? = nil) {
        showSearch = false
        // 若当前没有可用标签（如刚切到无痕），先建一个
        if currentTab == nil { newTab() }
        if let t = currentTab {
            t.load(url, searchTemplate: searchTemplate)
            enginePool.touch(t, current: t)
        }
        isBrowsing = true
        if !isIncognito { library.recordHistory(title: title ?? url, url: url) }
    }

    func goHome() {
        isBrowsing = false
    }

    /// 选择某个标签
    func select(_ tab: Tab) {
        currentTabID = tab.id
        isIncognito = tab.isIncognito
        if tab.isHome {
            isBrowsing = false
        } else {
            tab.activateIfNeeded(searchTemplate: searchTemplate)
            enginePool.touch(tab, current: tab)
            isBrowsing = true
        }
        showTabs = false
    }

    /// 后退：优先网页历史，无历史则退回主页
    func back() {
        if let engine, engine.canGoBack { engine.goBack() }
        else { goHome() }
    }

    func forward() {
        if let engine, engine.canGoForward { engine.goForward() }
    }

    func newTab() {
        let tab = Tab(isHome: true, isIncognito: isIncognito)
        tabIndex[tab.id] = tab
        if isIncognito { incognitoTabs.insert(tab, at: 0) } else { tabs.insert(tab, at: 0) }
        currentTabID = tab.id
        goHome()
        showTabs = false
    }

    func close(_ tab: Tab) {
        let wasCurrent = tab.id == currentTabID
        enginePool.remove(tab)
        tabIndex[tab.id] = nil
        withAnimation {
            if isIncognito { incognitoTabs.removeAll { $0.id == tab.id } }
            else { tabs.removeAll { $0.id == tab.id } }
        }
        if wasCurrent {
            currentTabID = activeTabs.first?.id
            isBrowsing = false
        }
    }

    func closeAllActive() {
        let closing = activeTabs
        for t in closing { enginePool.remove(t); tabIndex[t.id] = nil }
        withAnimation {
            if isIncognito { incognitoTabs.removeAll() } else { tabs.removeAll() }
        }
        currentTabID = nil
        isBrowsing = false
    }

    func toggleIncognito() {
        withAnimation { isIncognito.toggle() }
        currentTabID = activeTabs.first?.id
        if let t = currentTab, !t.isHome {
            t.activateIfNeeded(searchTemplate: searchTemplate)
            enginePool.touch(t, current: t)
            isBrowsing = true
        } else {
            isBrowsing = false
        }
    }
}

// MARK: - 示例数据
enum SampleData {
    static let quickLinks: [QuickLink] = [
        .init(title: "百度", url: "baidu.com", glyph: "百", color: Color(hex: 0x2932E1)),
        .init(title: "搜狗", url: "sogou.com", glyph: "搜", color: Color(hex: 0xFB6022)),
        .init(title: "Google", url: "google.com", glyph: "G", color: Color(hex: 0x4285F4)),
        .init(title: "Bing", url: "bing.com", glyph: "b", color: Color(hex: 0x008373)),
        .init(title: "神马搜索", url: "sm.cn", glyph: "神", color: Color(hex: 0xFF7A00)),
        .init(title: "360搜索", url: "so.com", glyph: "360", color: Color(hex: 0x10B266)),
        .init(title: "优酷", url: "youku.com", glyph: "优", color: Color(hex: 0x1AA1E1)),
        .init(title: "腾讯视频", url: "v.qq.com", glyph: "腾", color: Color(hex: 0xFF9B00)),
        .init(title: "微博", url: "weibo.com", glyph: "微", color: Color(hex: 0xE6162D)),
        .init(title: "网址导航", url: "hao123.com", glyph: "", color: Color(hex: 0x0A84FF), symbol: "safari.fill"),
        .init(title: "知乎", url: "zhihu.com", glyph: "知", color: Color(hex: 0x0066FF)),
        .init(title: "B站", url: "bilibili.com", glyph: "B", color: Color(hex: 0xFB7299)),
    ]

    @MainActor static func makeTabs() -> [Tab] {
        [
            Tab(isHome: true),
            Tab(isHome: false, placeholderTitle: "天行九歌 第1集 超清HD - YouTube",
                placeholderURL: "youtube.com", tint: Color(hex: 0x4A90D9)),
            Tab(isHome: false, placeholderTitle: "百度一下，你就知道",
                placeholderURL: "baidu.com", tint: Color(hex: 0x2932E1)),
        ]
    }

    static let bookmarks: [Bookmark] = {
        let common = Bookmark(title: "常用网站", url: "", glyph: "", colorHex: 0x0A84FF, isFolder: true)
        let tech = Bookmark(title: "技术资料", url: "", glyph: "", colorHex: 0xFF9500, isFolder: true)
        return [
            common, tech,
            .init(title: "百度一下", url: "baidu.com", glyph: "百", colorHex: 0x2932E1, parentID: common.id),
            .init(title: "知乎 - 有问题，就会有答案", url: "zhihu.com", glyph: "知", colorHex: 0x0066FF, parentID: common.id),
            .init(title: "GitHub", url: "github.com", glyph: "G", colorHex: 0x24292E, parentID: tech.id),
            .init(title: "哔哩哔哩", url: "bilibili.com", glyph: "B", colorHex: 0xFB7299),
            .init(title: "豆瓣", url: "douban.com", glyph: "豆", colorHex: 0x2D963D),
        ]
    }()

    static let history: [HistorySection] = [
        .init(title: "今天", items: [
            .init(title: "天行九歌 第1集 - YouTube", url: "youtube.com/watch", time: "14:32", glyph: "Y", colorHex: 0xFF0000),
            .init(title: "百度一下，你就知道", url: "baidu.com", time: "13:10", glyph: "百", colorHex: 0x2932E1),
            .init(title: "GitHub: Let's build", url: "github.com", time: "11:05", glyph: "G", colorHex: 0x24292E),
        ]),
        .init(title: "昨天", items: [
            .init(title: "知乎 - 发现", url: "zhihu.com", time: "21:48", glyph: "知", colorHex: 0x0066FF),
            .init(title: "哔哩哔哩 - 番剧", url: "bilibili.com", time: "20:12", glyph: "B", colorHex: 0xFB7299),
        ]),
        .init(title: "更早", items: [
            .init(title: "豆瓣电影 Top250", url: "douban.com", time: "06-18", glyph: "豆", colorHex: 0x2D963D),
        ]),
    ]

}
