import SwiftUI
import Combine

/// 全局浏览器状态。本阶段聚焦 UI 与流程，数据均为示例数据。
@MainActor
final class BrowserViewModel: ObservableObject {

    // MARK: - 浏览状态
    /// 当前是否处于网页浏览态（false = 主页 / 新标签页）
    @Published var isBrowsing: Bool = false
    @Published var isIncognito: Bool = false
    /// 网页夜间模式：**仅作用于网页内容**（注入反色 CSS），不影响 App 自身外观（外观由 `appearanceMode` 决定）。持久化。
    @Published var isNightMode: Bool = false { didSet { DiskStore.save(isNightMode, to: "night.json") } }
    /// 无图模式：派生自无图插件是否启用（同广告拦截，单一真相源 = PluginStore）。
    @Published private(set) var isNoImageMode: Bool = false
    /// 广告拦截状态：派生自广告类插件是否启用（单一真相源 = PluginStore）。
    /// 只读镜像——通过 `toggleAdBlock()` 驱动插件，避免开关与真实拦截脱节。
    @Published private(set) var isAdBlockOn: Bool = true
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

    /// App 自身配色：只由外观模式决定。网页夜间模式不再强制整个 App 变深色（那会劫持主页/设置/菜单）。
    var resolvedScheme: ColorScheme? { appearanceMode.scheme }
    /// 当前默认搜索引擎（持久化）。`searchTemplate` 由它派生，供 WebEngine.normalize 使用。
    @Published var searchEngine: SearchEngine = SearchEngine.builtIn[0] {
        didSet { DiskStore.save(searchEngine, to: "search_engine.json") }
    }
    /// 用户自定义搜索引擎（持久化）。
    @Published var customEngines: [SearchEngine] = [] {
        didSet { DiskStore.save(customEngines, to: "custom_engines.json") }
    }
    var searchTemplate: String { searchEngine.template }
    var allSearchEngines: [SearchEngine] { SearchEngine.builtIn + customEngines }

    /// 搜索历史（最近输入的关键词/网址，去重置顶，上限 12，持久化）
    @Published var searchHistory: [String] = [] { didSet { DiskStore.save(searchHistory, to: "search_history.json") } }
    func recordSearch(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        var h = searchHistory
        h.removeAll { $0 == t }
        h.insert(t, at: 0)
        if h.count > 12 { h.removeLast(h.count - 12) }
        searchHistory = h
    }
    func removeSearch(_ q: String) { searchHistory.removeAll { $0 == q } }
    func clearSearchHistory() { searchHistory = [] }

    /// 新增自定义引擎并设为当前。
    func addCustomEngine(name: String, template: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedTpl = template.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedTpl.isEmpty else { return }
        let e = SearchEngine(name: trimmedName, template: trimmedTpl,
                             glyph: String(trimmedName.prefix(1)).uppercased(), colorHex: 0x0A84FF)
        customEngines.removeAll { $0.id == e.id }   // 同名覆盖
        customEngines.append(e)
        searchEngine = e
    }
    func removeCustomEngine(_ e: SearchEngine) {
        customEngines.removeAll { $0.id == e.id }
        if searchEngine.id == e.id { searchEngine = SearchEngine.builtIn[0] }
    }

    /// 当前激活标签的网页引擎
    var engine: WebEngine? { currentTab?.engine }
    /// 当前页面地址 / 标题（用于网站设置、二维码等只读展示）
    var currentURL: String { currentTab?.displayURL ?? "" }
    var currentTitle: String { currentTab?.displayTitle ?? "" }

    // MARK: - 路由（全屏页面）
    enum Route: Identifiable {
        case bookmarks, history, downloads, files, settings
        case reading, imageViewer, comic, toolbox, qrScanner, reader, translate
        case jsExtensions, devtools, cookies, gestures, plugins, searchEngine
        case readingList

// 2) routeView(_:) 映射加 case（精确替换 RootView.swift）
        var id: String { String(describing: self) }
    }
    @Published var route: Route?

    // MARK: - 弹出层
    @Published var showMenu = false
    @Published var showTabs = false
    @Published var showWebsiteSettings = false
    @Published var showControlPanel = false
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
    @Published var quickLinks: [QuickLink] = SampleData.quickLinks {
        didSet { DiskStore.save(quickLinks, to: "quicklinks.json") }
    }
    /// 新增快捷网站（持久化）
    func addQuickLink(title: String, url: String) {
        let u = url.trimmingCharacters(in: .whitespaces)
        guard !u.isEmpty else { return }
        let name = title.trimmingCharacters(in: .whitespaces).isEmpty ? u : title.trimmingCharacters(in: .whitespaces)
        let palette: [UInt] = [0x2932E1, 0xFB6022, 0x34C759, 0xFF375F, 0xAF52DE, 0xFF9500, 0x0A84FF]
        quickLinks.append(QuickLink(title: name, url: u, glyph: String(name.prefix(1)).uppercased(),
                                    colorHex: palette[quickLinks.count % palette.count]))
    }
    /// 书签 + 历史拆到独立存储层（见 LibraryStore）
    let library = LibraryStore()
    /// 下载管理器引用（App 启动时注入）。供长按链接「下载」回调使用，
    /// 使该回调能随每个被激活的引擎统一绑定（见 `bindActiveEngine`），而非只挂在某一个引擎上。
    weak var downloadManager: DownloadManager?

    // MARK: - 标签页（每个标签独立引擎）
    @Published var tabs: [Tab] = SampleData.makeTabs()
    @Published var incognitoTabs: [Tab] = []
    /// 当前激活模式的当前标签 id（视图据此高亮/取 currentTab）。
    @Published var currentTabID: UUID?
    /// 两个模式各自记住自己的当前标签，互相切换时恢复，而不是每次跳回第一个。
    /// 非激活模式的值存这里；激活模式的值即 `currentTabID`。
    private var normalCurrentID: UUID?
    private var incognitoCurrentID: UUID?
    /// 普通 / 无痕模式各自「当前标签」的统一读取（无论当前激活哪个模式）。
    private var savedNormalID: UUID? { isIncognito ? normalCurrentID : currentTabID }
    private var savedIncognitoID: UUID? { isIncognito ? currentTabID : incognitoCurrentID }

    /// id → Tab 索引，保证海量标签下 currentTab 查找为 O(1)（避免每帧线性扫描）。
    private var tabIndex: [UUID: Tab] = [:]
    /// 活跃引擎 LRU 上限池：海量标签时只保留最近 N 个 WKWebView，其余回收。
    let enginePool = EnginePool()

    /// Combine 订阅容器（插件状态镜像、内容规则重载）。
    private var cancellables = Set<AnyCancellable>()
    /// 一次性标志：内容规则下次重编译完成后重载当前页（由广告/无图开关置位）。
    private var reloadCurrentOnRulesChange = false

    /// 手势按钮配置（持久化）
    @Published var gesture = GestureConfig() { didSet { DiskStore.save(gesture, to: "gestures.json") } }

    /// 底部工具栏按钮顺序（可自定义、持久化）。`.gesture` 仅在手势为「工具栏」放置时存在。
    @Published var toolbarItems: [ToolbarItemKind] = [.incognito, .search, .menu, .tabs, .home] {
        didSet { DiskStore.save(toolbarItems, to: "toolbar.json") }
    }
    /// 旧的内置默认布局（用于一次性迁移到新默认）
    private static let legacyToolbars: [[ToolbarItemKind]] = [
        [.back, .forward, .menu, .tabs, .home],
        [.night, .search, .menu, .tabs, .home],
    ]

    /// 切换手势放置方式：工具栏模式则把 `.gesture` 并入工具栏，悬浮模式则移出。
    func setGesturePlacement(_ p: GesturePlacement) {
        gesture.placement = p
        if p == .toolbar {
            if !toolbarItems.contains(.gesture), toolbarItems.count < 8 { toolbarItems.append(.gesture) }
        } else {
            toolbarItems.removeAll { $0 == .gesture }
        }
    }

    // MARK: - 工具栏自定义（1…8 个，任意功能）
    func addToolbarItem(_ k: ToolbarItemKind) {
        guard toolbarItems.count < 8, !toolbarItems.contains(k) else { return }
        toolbarItems.append(k)
        if k == .gesture { gesture.placement = .toolbar }
    }
    func removeToolbarItem(_ k: ToolbarItemKind) {
        guard toolbarItems.count > 1 else { return }
        toolbarItems.removeAll { $0 == k }
        if k == .gesture { gesture.placement = .floating }
    }
    func moveToolbarItems(from: IndexSet, to: Int) {
        toolbarItems.move(fromOffsets: from, toOffset: to)
    }

    /// 底部主菜单的功能项（**分页**，可左右滑动；每页可长按编辑/删除/拖动/添加，持久化）。目录见 `MenuCatalog`。
    @Published var menuItems: [[String]] = MenuCatalog.defaultPages {
        didSet { DiskStore.save(menuItems, to: "menu.json") }
    }
    /// 盾牌控制面板的快捷功能项顺序（网页相关操作，可编辑，持久化）。目录见 `ControlPanelCatalog`。
    @Published var panelItems: [String] = ControlPanelCatalog.defaultTitles {
        didSet { DiskStore.save(panelItems, to: "panel.json") }
    }

    /// 当前页面是否检测到可播放视频（由 `WebEngine.detectVideo` 在加载完成/按需刷新）。
    /// 决定是否显示「悬浮播放」入口——没有视频就不显示，避免「有菜单没视频」。
    @Published var hasVideo: Bool = false

    /// 看图模式：当前页面提取出的图片地址
    @Published var pageImages: [String] = []

    /// 网址导航分类的展开状态（默认全展开，记住用户操作并持久化）
    @Published var navExpanded: Set<String> = Set(NavCatalog.categories.map(\.title)) {
        didSet { DiskStore.save(Array(navExpanded), to: "nav_expanded.json") }
    }

    /// 新建标签时自增，触发主体页面从左下角弹出的动画（RootView 观察）
    @Published private(set) var pagePopTrigger = 0
    /// 后台打开链接时自增，触发标签按钮的小动画（替代 toast）
    @Published private(set) var bgOpenTrigger = 0

    /// 查看源码弹层
    struct SourcePreview: Identifiable { let id = UUID(); let code: String }
    @Published var sourcePreview: SourcePreview?

    // MARK: - 网页导出 / 打印（基于当前 WKWebView）
    /// 安全文件名（取标题或地址，去非法字符，限长）。
    private func pageFileName(ext: String) -> String {
        let raw = currentTitle.isEmpty ? currentURL : currentTitle
        let cleaned = raw.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\t")).joined()
        let base = cleaned.trimmingCharacters(in: .whitespaces).prefix(40)
        return "\(base.isEmpty ? "page" : base).\(ext)"
    }

    private func writeToDownloads(_ data: Data, name: String, successSymbol: String) {
        let url = DownloadManager.downloadsDirectory.appendingPathComponent(name)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            do {
                try data.write(to: url, options: .atomic)
                Task { @MainActor in self?.showToast("已保存 \(name)", symbol: successSymbol) }
            } catch {
                Task { @MainActor in self?.showToast("保存失败", symbol: "exclamationmark.circle") }
            }
        }
    }

    func saveCurrentPDF() {
        guard isBrowsing, let engine else { showToast("请先打开网页", symbol: "exclamationmark.circle"); return }
        showToast("正在导出 PDF…", symbol: "doc.richtext")
        let name = pageFileName(ext: "pdf")
        engine.exportPDF { [weak self] data in
            guard let data else { self?.showToast("导出失败", symbol: "exclamationmark.circle"); return }
            self?.writeToDownloads(data, name: name, successSymbol: "doc.richtext")
        }
    }

    func saveCurrentHTML() {
        guard isBrowsing, let engine else { showToast("请先打开网页", symbol: "exclamationmark.circle"); return }
        let name = pageFileName(ext: "html")
        engine.fetchHTML { [weak self] html in
            guard let data = html?.data(using: .utf8) else { self?.showToast("获取源码失败", symbol: "exclamationmark.circle"); return }
            self?.writeToDownloads(data, name: name, successSymbol: "doc.plaintext")
        }
    }

    func viewSource() {
        guard isBrowsing, let engine else { showToast("请先打开网页", symbol: "exclamationmark.circle"); return }
        engine.fetchHTML { [weak self] html in
            self?.sourcePreview = SourcePreview(code: html ?? "（无法获取源码）")
        }
    }

    func printCurrent() {
        guard isBrowsing, let engine else { showToast("请先打开网页", symbol: "exclamationmark.circle"); return }
        engine.printPage(jobName: currentTitle)
    }

    func findInPage() {
        guard isBrowsing, let engine else { showToast("请先打开网页", symbol: "exclamationmark.circle"); return }
        engine.presentFind()
    }

    init() {
        if let g = DiskStore.load(GestureConfig.self, from: "gestures.json") { gesture = g }
        if let e = DiskStore.load(SearchEngine.self, from: "search_engine.json") { searchEngine = e }
        if let c = DiskStore.load([SearchEngine].self, from: "custom_engines.json") { customEngines = c }
        if let t = DiskStore.load([ToolbarItemKind].self, from: "toolbar.json"),
           !Self.legacyToolbars.contains(t) { toolbarItems = t }   // 旧默认布局迁移到新默认
        if let sh = DiskStore.load([String].self, from: "search_history.json") { searchHistory = sh }
        if let ne = DiskStore.load([String].self, from: "nav_expanded.json") { navExpanded = Set(ne) }
        if let ql = DiskStore.load([QuickLink].self, from: "quicklinks.json") { quickLinks = ql }
        if let n = DiskStore.load(Bool.self, from: "night.json") { isNightMode = n }
        if let b = DiskStore.load(Bool.self, from: "block_redirects.json") { blockRedirects = b }
        if let m = DiskStore.load([[String]].self, from: "menu.json"), !m.isEmpty { menuItems = m }
        if let pn = DiskStore.load([String].self, from: "panel.json") { panelItems = pn }
        if let snd = DiskStore.load(Bool.self, from: "show_nav_directory.json") { showNavDirectory = snd }
        if let nth = DiskStore.load(Bool.self, from: "new_tab_opens_homepage.json") { newTabOpensHomepage = nth }
        if let hu = DiskStore.load(String.self, from: "homepage_url.json") { homepageURL = hu }
        if let dvr = DiskStore.load(Double.self, from: "default_video_rate.json") { defaultVideoRate = dvr }
        // 不变式校正：gesture ∈ toolbarItems ⟺ 放置方式为工具栏（防旧数据不一致导致空槽）
        let gestureInToolbar = toolbarItems.contains(.gesture)
        if (gesture.placement == .toolbar) != gestureInToolbar {
            gesture.placement = gestureInToolbar ? .toolbar : .floating
        }
        // 恢复上次的标签（普通 + 无痕都持久化）。属性观察器在 init 中不触发，恢复不会回写。
        if let state = DiskStore.load(TabsState.self, from: "tabs.json"),
           !(state.tabs.isEmpty && state.incognitoTabs.isEmpty) {
            if !state.tabs.isEmpty { tabs = state.tabs.map { Tab($0) } }
            incognitoTabs = state.incognitoTabs.map { Tab($0, isIncognito: true) }
            normalCurrentID = state.currentID ?? tabs.first?.id
            incognitoCurrentID = state.incognitoCurrentID ?? incognitoTabs.first?.id
        } else {
            normalCurrentID = tabs.first?.id
        }
        currentTabID = normalCurrentID   // 启动进入普通模式
        for t in tabs { tabIndex[t.id] = t }
        for t in incognitoTabs { tabIndex[t.id] = t }

        // 广告拦截 / 无图开关镜像对应插件的启用状态（PluginStore 为单一真相源）。
        // assign(to:) 不强引用 self，订阅时即用当前值同步一次。
        PluginStore.shared.$plugins
            .map { $0.contains { $0.category == .adblock && $0.installed && $0.enabled } }
            .assign(to: &$isAdBlockOn)
        PluginStore.shared.$plugins
            .map { $0.contains { $0.id == "noimage.block" && $0.installed && $0.enabled } }
            .assign(to: &$isNoImageMode)

        // 内容规则重编译完成后（异步），若刚由开关触发则重载当前页使其立即生效。
        PluginStore.shared.$compiledRuleLists
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, self.reloadCurrentOnRulesChange else { return }
                self.reloadCurrentOnRulesChange = false
                if self.isBrowsing, let t = self.currentTab, t.hasEngine {
                    t.engine.refreshContentRules(reload: true)
                }
            }
            .store(in: &cancellables)
    }

    /// 切换广告拦截：驱动所有已安装的广告类插件启用/停用；isAdBlockOn 经由上面的管道回流刷新。
    func toggleAdBlock() {
        let target = !isAdBlockOn
        for p in PluginStore.shared.plugins where p.category == .adblock && p.installed {
            PluginStore.shared.setEnabled(p, target)
        }
        reloadCurrentOnRulesChange = true
        showToast(target ? "已开启广告拦截" : "已关闭广告拦截", symbol: "shield.lefthalf.filled")
    }

    /// 切换无图模式：驱动无图内容规则插件；切换后当前页重载生效。
    func toggleNoImage() {
        guard let p = PluginStore.shared.plugins.first(where: { $0.id == "noimage.block" }) else { return }
        let target = !isNoImageMode
        PluginStore.shared.setEnabled(p, target)
        reloadCurrentOnRulesChange = true
        showToast(target ? "已开启无图模式" : "已关闭无图模式", symbol: "photo.on.rectangle.angled")
    }

    // MARK: - 标签持久化（合并写，避免连续增删反复整表编码）
    private var tabPersistWork: DispatchWorkItem?
    /// 标签结构/地址变化后调用：延迟合并为一次落盘（普通 + 无痕都持久化）。
    func scheduleTabPersist() {
        tabPersistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistTabsNow() }
        tabPersistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    /// 立即落盘（供 App 进入后台时调用，捕获最新标题/地址）。
    func persistTabsNow() {
        // 快照在主线程取（Tab 是 @MainActor），编码+写盘交给后台，避免海量标签整表编码卡主线程。
        let state = TabsState(tabs: tabs.map(\.snapshot), currentID: savedNormalID,
                              incognitoTabs: incognitoTabs.map(\.snapshot), incognitoCurrentID: savedIncognitoID)
        DiskStore.saveAsync(state, to: "tabs.json")
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
        if gesture.haptics { Haptics.soft() }
        showToast(action.title, symbol: action.symbol)
    }

    // MARK: - 统一功能分发（菜单 + 控制面板按标题共用）
    /// 某功能当前是否处于「开」状态（用于开关型功能的高亮/小开关）。
    func actionIsOn(_ title: String) -> Bool {
        switch title {
        case "无痕模式": return isIncognito
        case "夜间模式": return isNightMode
        case "无图模式": return isNoImageMode
        case "广告拦截": return isAdBlockOn
        case "电脑版", "桌面版网站": return isDesktopMode
        default: return false
        }
    }

    /// 执行某功能（按标题）。返回 true 表示宿主弹层（菜单/控制面板）应关闭；开关型停留返回 false。
    @discardableResult
    func performMenuAction(_ title: String) -> Bool {
        switch title {
        // 路由页面
        case "设置": route = .settings
        case "书签": route = .bookmarks
        case "历史": route = .history
        case "下载": route = .downloads
        case "文件": route = .files
        case "阅读模式": openReadingMode()
        case "漫画模式": openComicMode()
        case "网页翻译": translateCurrentPage()
        case "工具箱": route = .toolbox
        case "开发者工具": route = .devtools
        case "Cookie管理": route = .cookies
        case "二维码", "扫码": route = .qrScanner
        case "JavaScript扩展", "JavaScript 脚本": route = .jsExtensions
        case "搜索引擎": route = .searchEngine
        case "电子书": route = .reader
        case "看图模式", "查看图片": openImageMode()
        // 页面操作（真实）
        case "刷新": guardEngine { $0.reload() }
        case "后退": back()
        case "前进": forward()
        case "查看源码": viewSource()
        case "保存PDF": saveCurrentPDF()
        case "保存HTML": saveCurrentHTML()
        case "打印": printCurrent()
        case "页面搜索", "站内搜索", "页面查找": findInPage()
        case "复制网址":
            guard !currentURL.isEmpty else { showToast("无可复制的网址", symbol: "exclamationmark.circle"); return false }
            UIPasteboard.general.string = currentURL
            showToast("已复制网址", symbol: "doc.on.doc")
        case "分享": shareCurrentPage()
        case "滚动到顶": guardEngine { $0.webView.evaluateJavaScript("window.scrollTo({top:0,behavior:'smooth'})") }
        case "滚动到底": guardEngine { $0.webView.evaluateJavaScript("window.scrollTo({top:document.body.scrollHeight,behavior:'smooth'})") }
        case "下载资源", "下载当前资源": showDownloadConfirm = true
        case "视频悬浮", "画中画": return openVideoFloat()
        case "标记广告": showMarkAds = true
        case "网站设置": showWebsiteSettings = true
        case "视频截图": captureVideoFrame()
        case "镜像播放": toggleVideoMirror()
        case "后台播放": enableBackgroundPlayback()
        case "AirPlay": showAirPlay = true
        case "Eruda": guardEngine { $0.injectDevConsole(.eruda) }; showToast("正在注入 Eruda 控制台…", symbol: "ladybug")
        case "vConsole": guardEngine { $0.injectDevConsole(.vconsole) }; showToast("正在注入 vConsole 控制台…", symbol: "terminal")
        case "WebArchive": saveWebArchive()
        case "网页长截图": saveFullScreenshot()
case "生成二维码": showQRGenerate = true
case "识别图中码": qrAutoPickPhoto = true; route = .qrScanner
        // 自动刷新: 循环切换档位(开关型语义, 选择关闭宿主弹层)
        case "自动刷新": toggleAutoRefresh()
        // 全屏模式: 隐藏底部工具栏
        case "全屏模式": toggleFullScreen()
        // 视频单曲循环: 对页面首个 <video> 切换 loop
        case "单曲循环":
            guardEngine { engine in
                engine.videoToggleLoop { [weak self] on in
                    guard let self else { return }
                    guard let on else { self.showToast("未检测到视频", symbol: "play.slash"); return }
                    self.showToast(on ? "已开启单曲循环" : "已关闭单曲循环", symbol: "repeat.1")
                }
            }
        case "主页": goHome()
        // 开关型（停留，不关闭弹层）
        case "无痕模式": toggleIncognito(); return false
        case "夜间模式": isNightMode.toggle(); return false
        case "无图模式": toggleNoImage(); return false
        case "广告拦截": toggleAdBlock(); return false
        case "电脑版", "桌面版网站": isDesktopMode.toggle(); return false
        // 拦截跳转（开关型，停留不关弹层）
        case "拦截跳转": toggleBlockRedirects(); return false
        // 查看站点证书（动作型，关闭宿主弹层后弹证书 sheet）
        case "站点证书", "查看证书", "查看站点证书": viewCertificate()
        case "媒体嗅探": openMediaSniffer()

case "稍后读": saveToReadingList()
case "阅读列表": route = .readingList
        default:
            showToast("「\(title)」暂未实现", symbol: "hammer")
            return false
        }
        return true
    }

    /// 需要当前网页的操作的统一守卫：无网页时提示。
    private func guardEngine(_ body: (WebEngine) -> Void) {
        guard isBrowsing, let engine else { showToast("请先打开网页", symbol: "exclamationmark.circle"); return }
        body(engine)
    }

    // MARK: - 分享当前页
    struct ShareItem: Identifiable { let id = UUID(); let url: URL }
    @Published var shareItem: ShareItem?
    func shareCurrentPage() {
        let s = currentURL
        guard !s.isEmpty else { showToast("无可分享的页面", symbol: "exclamationmark.circle"); return }
        let str = s.hasPrefix("http") ? s : "https://" + s
        guard let u = URL(string: str) else { showToast("无可分享的页面", symbol: "exclamationmark.circle"); return }
        shareItem = ShareItem(url: u)
    }

    // MARK: - 视频悬浮（先真实检测页面是否有视频）
    /// 打开悬浮播放器前先检测页面视频；无视频则提示，不弹空壳播放器。
    @discardableResult
    func openVideoFloat() -> Bool {
        guard isBrowsing, let engine else { showToast("请先打开网页", symbol: "exclamationmark.circle"); return false }
        engine.detectVideo { [weak self] found in
            guard let self else { return }
            self.hasVideo = found
            if found { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { self.showVideoFloat = true } }
            else { self.showToast("未检测到视频", symbol: "play.slash") }
        }
        return true
    }

    /// 刷新「当前标签是否有视频」（切标签/加载完成时调用），驱动悬浮入口的显隐。
    func refreshVideoPresence(for tab: Tab) {
        guard tab.hasEngine, tab.id == currentTabID else { return }
        tab.engine.detectVideo { [weak self, weak tab] found in
            guard let self, let tab, tab.id == self.currentTabID else { return }
            self.hasVideo = found
        }
    }

// MARK: - 阅读模式（正文抽取）

/// 当前抽取出的正文（标题 + 来源 host + 段落）。类型定义在 ReadingModeView.swift。
@Published var readingArticle: ReadableArticle = .empty

/// 进入阅读模式：从当前页面抽取正文（仿 openImageMode 的「先取数据再 route」）。
/// 非浏览态无网页可抽取，提示后不进入。
func openReadingMode() {
    guard isBrowsing, let engine else {
        showToast("请先打开网页", symbol: "exclamationmark.circle")
        return
    }
    engine.fetchReadableArticle { [weak self] article in
        self?.readingArticle = article
        self?.route = .reading
    }
}
    // MARK: - 网页保存增强（WebArchive / 整页长截图）

    /// 保存当前网页为 WebArchive（.webarchive，可被 Safari/系统还原完整离线网页）。
    func saveWebArchive() {
        guard isBrowsing, let engine else { showToast("请先打开网页", symbol: "exclamationmark.circle"); return }
        showToast("正在保存 WebArchive…", symbol: "archivebox")
        let name = pageFileName(ext: "webarchive")
        engine.exportWebArchive { [weak self] data in
            guard let data else { self?.showToast("保存失败", symbol: "exclamationmark.circle"); return }
            self?.writeToDownloads(data, name: name, successSymbol: "archivebox")
        }
    }

    /// 保存当前网页整页长截图（含视口以外内容）为 PNG。
    func saveFullScreenshot() {
        guard isBrowsing, let engine else { showToast("请先打开网页", symbol: "exclamationmark.circle"); return }
        showToast("正在生成长截图…", symbol: "rectangle.portrait.and.arrow.right")
        let name = pageFileName(ext: "png")
        engine.fullPageSnapshot { [weak self] image in
            guard let data = image?.pngData() else { self?.showToast("截图失败", symbol: "exclamationmark.circle"); return }
            self?.writeToDownloads(data, name: name, successSymbol: "rectangle.portrait.and.arrow.right")
        }
    }
// MARK: - 二维码（生成当前页 / 识别图中码）
/// 生成当前页二维码弹层标志（RootView 以 .sheet 呈现 QRGenerateSheet）。
@Published var showQRGenerate = false
/// 进入扫码页后是否自动弹出相册（供菜单「识别图中码」直达相册识别）。
@Published var qrAutoPickPhoto = false
    // MARK: - 自动刷新（循环档位: 0=关 / 15 / 30 / 60 秒）
    /// 当前自动刷新间隔(秒), 0 表示关闭。仅作展示与档位记忆, 不持久化(刷新行为偏临时)。
    @Published private(set) var autoRefreshSeconds: Int = 0
    /// 自动刷新计时器(主线程 Timer)。开档时创建, 关档/换档时失效。
    private var autoRefreshTimer: Timer?
    /// 可循环的档位序列。
    private static let autoRefreshSteps: [Int] = [0, 15, 30, 60]

    /// 循环切换自动刷新档位(0→15→30→60→0), 并按新档位启停计时器、给出提示。
    func toggleAutoRefresh() {
        let steps = Self.autoRefreshSteps
        let idx = steps.firstIndex(of: autoRefreshSeconds) ?? 0
        let next = steps[(idx + 1) % steps.count]
        autoRefreshSeconds = next
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
        if next > 0 {
            // 到点刷新当前网页; 非浏览态(主页)或无引擎时跳过, 不打断也不报错。
            let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(next), repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isBrowsing, let engine = self.engine else { return }
                    engine.reload()
                }
            }
            autoRefreshTimer = timer
            showToast("自动刷新: 每 \(next) 秒", symbol: "arrow.triangle.2.circlepath")
        } else {
            showToast("已关闭自动刷新", symbol: "arrow.triangle.2.circlepath")
        }
    }

    // MARK: - 全屏模式（隐藏底部工具栏, 由 RootView 据此条件渲染）
    /// 是否处于全屏浏览(隐藏底部工具栏, 显示浮动退出按钮)。
    @Published var isFullScreen: Bool = false
    /// 切换全屏模式, 并给出提示。
    func toggleFullScreen() {
        withAnimation(.easeInOut(duration: 0.2)) { isFullScreen.toggle() }
        showToast(isFullScreen ? "已进入全屏" : "已退出全屏",
                  symbol: isFullScreen ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
    }
// MARK: - 网站设置（按当前域名）真实化

/// User-Agent 选项标签（供网站设置 Picker 复用，单一真相源）。
static let userAgentOptions = ["默认", "iPhone", "iPad", "Mac", "Windows"]

/// 当前页面 host（地址栏展示已是 host 优先；用于按站清数据/展示）。
var currentHost: String { currentURL }

/// 当前引擎 customUserAgent 对应的选项标签（用于面板回显）。
var currentUserAgentLabel: String {
    guard let ua = engine?.webView.customUserAgent else { return "默认" }
    return Self.userAgentLabel(forUA: ua)
}

/// 标签 -> UA 串映射；返回 nil 表示用系统默认 UA。
static func userAgentString(for label: String) -> String? {
    switch label {
    case "iPhone":  return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    case "iPad":    return "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    case "Mac":     return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    case "Windows": return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    default:        return nil   // 默认：交还系统 UA
    }
}

/// 由 UA 串反查选项标签（用于面板回显，未知串归为「默认」）。
private static func userAgentLabel(forUA ua: String) -> String {
    for label in userAgentOptions where userAgentString(for: label) == ua { return label }
    return "默认"
}

/// 设置当前站点 User-Agent（真实写 customUserAgent 并重载生效）。
func setSiteUserAgent(_ label: String) {
    guard isBrowsing, let engine else { showToast("请先打开网页", symbol: "exclamationmark.circle"); return }
    let ua = Self.userAgentString(for: label)
    // UA 与「桌面版网站」开关同写 customUserAgent，last-writer-wins：手动选 UA 时把桌面开关对齐避免显示矛盾。
    isDesktopMode = (label == "Mac" || label == "Windows")
    engine.setUserAgent(ua)
    showToast(label == "默认" ? "已恢复默认 UA" : "已切换为 \(label) UA", symbol: "person.crop.circle")
}

/// 清除本站 Cookie / 缓存（按当前 host 的数据记录，异步，回主线程提示）。
func clearSiteCookies() {
    guard isBrowsing, let engine, !currentHost.isEmpty else {
        showToast("请先打开网页", symbol: "exclamationmark.circle"); return
    }
    let host = currentHost
    engine.clearSiteData(host: host) { [weak self] in
        self?.showToast("已清除「\(host)」的 Cookie 与缓存", symbol: "trash")
    }
}

/// 清除本站广告规则：对当前页重新套用所有启用的内容拦截规则并重载（相当于刷新本站拦截状态）。
func clearSiteAdRules() {
    guard isBrowsing, let engine else { showToast("请先打开网页", symbol: "exclamationmark.circle"); return }
    engine.refreshContentRules(reload: true)
    showToast("已重置本站广告规则", symbol: "shield.lefthalf.filled")
}

/// 站点权限重置：把该站的本地开关（夜间 / 桌面版 / 自定义 UA）恢复默认，并清掉本站数据。
func resetSitePermissions() {
    guard isBrowsing, let engine else { showToast("请先打开网页", symbol: "exclamationmark.circle"); return }
    let host = currentHost
    isNightMode = false
    isDesktopMode = false
    engine.setUserAgent(nil)
    if !host.isEmpty {
        engine.clearSiteData(host: host) { [weak self] in
            self?.showToast("已重置「\(host)」的站点设置", symbol: "arrow.counterclockwise")
        }
    } else {
        showToast("已重置站点设置", symbol: "arrow.counterclockwise")
    }
}

    // MARK: - workflow 批量功能（视频增强/AirPlay/漫画/翻译/PDF/文本/压缩）
    @Published var showAirPlay = false
    @Published var translateText: String = ""
    @Published var showTranslate: Bool = false
    struct PDFPreviewItem: Identifiable { let id = UUID(); let url: URL }
    @Published var pdfPreviewURL: PDFPreviewItem?
    @Published var textFileURL: URL?

    func captureVideoFrame() {
        guardEngine { [weak self] engine in
            engine.videoCaptureFrame { image in
                guard let self else { return }
                guard let data = image?.pngData() else { self.showToast("未检测到视频或无法截图", symbol: "camera.badge.ellipsis"); return }
                self.writeToDownloads(data, name: self.pageFileName(ext: "png"), successSymbol: "camera")
            }
        }
    }
    func toggleVideoMirror() {
        guardEngine { [weak self] engine in
            engine.videoToggleMirror { mirrored in
                guard let self else { return }
                guard let mirrored else { self.showToast("未检测到视频", symbol: "play.slash"); return }
                self.showToast(mirrored ? "已开启镜像播放" : "已关闭镜像播放", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
        }
    }
    func enableBackgroundPlayback() {
        guardEngine { [weak self] engine in
            guard let self else { return }
            do { try engine.enableBackgroundPlayback(); self.showToast("已开启后台播放", symbol: "play.circle") }
            catch { self.showToast("后台播放开启失败", symbol: "exclamationmark.circle") }
        }
    }
    /// 进入漫画模式：提取真实图片做长图阅读。
    func openComicMode() {
        guard isBrowsing, let engine else { pageImages = []; route = .comic; return }
        engine.fetchImageURLs { [weak self] urls in self?.pageImages = urls; self?.route = .comic }
    }
    /// 对给定文本弹系统翻译面板（iOS 17.4+）。
    func presentTranslation(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { showToast("没有可翻译的文本", symbol: "exclamationmark.circle"); return }
        if #available(iOS 17.4, *) { translateText = String(trimmed.prefix(2000)); showTranslate = true }
        else { showToast("翻译需要 iOS 17.4 或更高版本", symbol: "character.bubble") }
    }
    /// 翻译当前网页：优先选中文本, 否则抓正文。
    func translateCurrentPage() {
        if #available(iOS 17.4, *) {
            let selected = selectionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !selected.isEmpty { presentTranslation(selected); return }
            guard isBrowsing, let engine else { showToast("请先打开网页", symbol: "exclamationmark.circle"); return }
            engine.fetchPageText { [weak self] text in
                guard let self else { return }
                let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { self.showToast("未获取到页面文本", symbol: "exclamationmark.circle"); return }
                self.presentTranslation(t)
            }
        } else { route = .translate }
    }
    /// 用 PDF 阅读器打开下载目录内 PDF。
    func openPDF(fileName: String) {
        let url = DownloadManager.downloadsDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { showToast("文件不存在", symbol: "exclamationmark.circle"); return }
        pdfPreviewURL = PDFPreviewItem(url: url)
    }
    /// 以纯文本打开下载目录内文件。
    func openTextFile(named name: String) { textFileURL = DownloadManager.downloadsDirectory.appendingPathComponent(name) }
    /// 压缩下载目录里的图片。
    @discardableResult
    func compressImage(name: String) -> Bool {
        do {
            let result = try ImageCompressor.compress(fileName: name)
            let before = ByteCountFormatter.string(fromByteCount: result.originalBytes, countStyle: .file)
            let after = ByteCountFormatter.string(fromByteCount: result.compressedBytes, countStyle: .file)
            showToast("已压缩：\(before) → \(after)（省 \(Int((result.savedRatio*100).rounded()))%）", symbol: "photo.badge.arrow.down")
            return true
        } catch { showToast("压缩失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle.fill"); return false }
    }

// MARK: - 标记广告（点选元素 → 隐藏并按站持久化）
// 依赖：AdHideStore.shared（新文件）、engine.beginElementPick/cancelElementPick/applyAdHide（WebEngine 新方法）。

/// 进入元素拾取态：注入拾取层，开始隐藏选中的元素；每隐藏一个回调一次（带选择器）。
/// 选中即写入 AdHideStore（按当前 host 持久化）并立即注入隐藏 CSS。
func beginAdElementPick(onPick: @escaping (String) -> Void) {
    guard isBrowsing, let engine else {
        showToast("请先打开网页", symbol: "exclamationmark.circle")
        showMarkAds = false
        return
    }
    let host = engine.webView.url?.host
    engine.beginElementPick { [weak self, weak engine] selector in
        guard let self, let engine else { return }
        // 持久化该站规则并取回完整列表，立即整体注入隐藏 CSS。
        let all = AdHideStore.shared.add(selector, for: host)
        engine.applyAdHide(all)
        onPick(selector)
    }
}

/// 退出拾取态：移除拾取层监听（已隐藏的元素保持隐藏）。
func endAdElementPick() {
    engine?.cancelElementPick()
}

/// 撤销某条隐藏规则（按站移除并重注入剩余规则）。
func undoAdHide(selector: String) {
    guard let engine else { return }
    let host = engine.webView.url?.host
    let all = AdHideStore.shared.remove(selector, for: host)
    engine.applyAdHide(all)
}
// 在 @Published var oledBlack / wallpaper 等外观/偏好区域附近新增以下 4 个持久化偏好开关（didSet 落盘，init 末尾恢复）：

/// 主页第二屏「网址导航目录」是否显示（默认显示）。真实生效：HomeView 据此条件渲染第二页。
@Published var showNavDirectory: Bool = true { didSet { DiskStore.save(showNavDirectory, to: "show_nav_directory.json") } }
/// 新建标签页时是否直接打开主页地址（偏好，持久化）。
@Published var newTabOpensHomepage: Bool = false { didSet { DiskStore.save(newTabOpensHomepage, to: "new_tab_opens_homepage.json") } }
/// 主页地址（偏好，持久化，默认百度）。
@Published var homepageURL: String = "baidu.com" { didSet { DiskStore.save(homepageURL, to: "homepage_url.json") } }
/// 默认视频播放倍速（偏好，持久化，默认 1.0 倍速）。
@Published var defaultVideoRate: Double = 1.0 { didSet { DiskStore.save(defaultVideoRate, to: "default_video_rate.json") } }
// 加在 BrowserViewModel 弹出层标志区附近（与 showWebsiteSettings 等并列）：

    /// 拦截跨域自动跳转（页面级开关，按引擎生效，切标签时由 bindActiveEngine 同步）。持久化。
    @Published var blockRedirects: Bool = false { didSet { DiskStore.save(blockRedirects, to: "block_redirects.json") } }
    /// 证书详情 sheet 控制：非 nil 时呈现 CertificateView。
    @Published var certificateInfo: CertificateInfo?

    /// 切换「拦截跳转」并同步进当前引擎；停留弹层（开关型）。
    func toggleBlockRedirects() {
        blockRedirects.toggle()
        engine?.blockRedirects = blockRedirects
        showToast(blockRedirects ? "已开启拦截跳转" : "已关闭拦截跳转", symbol: blockRedirects ? "hand.raised.fill" : "hand.raised.slash")
    }

    /// 查看当前站点证书：从引擎缓存的 SecTrust 解析证书信息并弹出详情。
    func viewCertificate() {
        guard isBrowsing, let engine else { showToast("请先打开网页", symbol: "exclamationmark.circle"); return }
        guard let info = engine.certificateInfo(host: currentHost) else {
            showToast("未获取到证书信息", symbol: "lock.shield"); return
        }
        certificateInfo = info
    }

// 注意: 需在 bindActiveEngine(_:) 内补充两行（见 sharedFileEdits 对 BrowserViewModel.swift 的替换），
// 用于把 blockRedirects 同步进新激活引擎 + 绑定被拦截回调提示。
// 还需在 init 末尾恢复持久化（见 sharedFileEdits）。
// MARK: - 搜索联想词（真实接口）
// 放在 searchHistory 相关代码附近即可。

/// 搜索联想词建议（来自 Bing osjson 接口，随输入实时更新；空输入时为空）
@Published var searchSuggestions: [String] = []

/// 当前联想词请求任务（用于防抖与取消旧请求）
private var suggestTask: Task<Void, Never>?

/// 拉取联想词：防抖 + 取消旧请求；空 query 立即清空；
/// 用 Bing osjson 接口（HTTPS，免 Key），解析 JSON 数组第二元素 [词,[建议...]]，回主线程赋值。
func fetchSuggestions(_ q: String) {
    let keyword = q.trimmingCharacters(in: .whitespaces)
    // 取消上一个未完成的请求，避免乱序覆盖。
    suggestTask?.cancel()
    // 空输入直接清空，无需发请求。
    guard !keyword.isEmpty else {
        searchSuggestions = []
        return
    }
    // 网址/含协议或斜杠的输入不做联想（用户在敲地址）。
    if keyword.contains("://") || keyword.contains(" ") == false && keyword.contains(".") && !keyword.contains("。") {
        // 仅对疑似域名输入跳过联想；普通关键词照常联想。
        if keyword.contains(".") && !keyword.hasSuffix(".") && URL(string: keyword.hasPrefix("http") ? keyword : "https://\(keyword)") != nil && keyword.range(of: "[\\u4e00-\\u9fa5]", options: .regularExpression) == nil {
            searchSuggestions = []
            return
        }
    }
    suggestTask = Task { @MainActor [weak self] in
        // 防抖：等待 220ms，期间被取消则不发请求。
        try? await Task.sleep(nanoseconds: 220_000_000)
        if Task.isCancelled { return }
        guard let self else { return }
        let results = await Self.requestBingSuggestions(keyword)
        if Task.isCancelled { return }
        // 回主线程赋值（本类 @MainActor，await 后已在主线程）。
        self.searchSuggestions = results
    }
}

/// 调用 Bing osjson 联想接口并解析结果（非主线程网络，纯静态避免捕获 self）。
/// 返回示例 JSON: ["swift", ["swiftui","swift 教程", ...]]
private static func requestBingSuggestions(_ keyword: String) async -> [String] {
    guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
          let url = URL(string: "https://api.bing.com/osjson.aspx?query=\(encoded)") else {
        return []
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 6
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
        // 解析 [词, [建议...]]：取第二个元素的字符串数组。
        let json = try JSONSerialization.jsonObject(with: data)
        guard let arr = json as? [Any], arr.count >= 2, let list = arr[1] as? [String] else { return [] }
        return Array(list.prefix(8))
    } catch {
        // 网络/解析失败：静默降级为空建议（不抛错以免打断输入体验），但保留上下文供调试。
        #if DEBUG
        print("fetchSuggestions failed keyword=\(keyword) url=\(url) error=\(error)")
        #endif
        return []
    }
}

    // MARK: - 媒体嗅探（页面内 <video>/<audio> 地址收集 + 下载/复制/分享）
    /// 当前页面嗅探到的媒体命中（由 WebEngine.sniffMedia 填充）。
    @Published var mediaHits: [MediaHit] = []
    /// 媒体嗅探结果页呈现标志（RootView 以 .sheet 呈现 MediaSnifferView）。
    @Published var showMediaSniffer = false

    /// 打开媒体嗅探：先对当前页面嗅探音/视频地址，取回后再呈现结果页。
    /// 非浏览态无网页可嗅探，提示后不进入。
    func openMediaSniffer() {
        guard isBrowsing, let engine else {
            showToast("请先打开网页", symbol: "exclamationmark.circle")
            return
        }
        engine.sniffMedia { [weak self] hits in
            guard let self else { return }
            self.mediaHits = hits
            self.showMediaSniffer = true
        }
    }

    /// 下载某条媒体命中（交给 DownloadManager 真实下载到 Downloads 目录）。
    func downloadMediaHit(_ hit: MediaHit) {
        guard let manager = downloadManager else {
            showToast("下载服务未就绪", symbol: "exclamationmark.circle"); return
        }
        manager.start(urlString: hit.url)
        showToast("开始下载…", symbol: "arrow.down.circle")
    }

    /// 分享某条媒体命中地址（系统分享面板）。
    func shareMediaHit(_ hit: MediaHit) {
        guard let url = URL(string: hit.url) else {
            showToast("无效的媒体地址", symbol: "exclamationmark.circle"); return
        }
        shareItem = ShareItem(url: url)
    }

// MARK: - 稍后读 / 离线阅读列表
/// 抓当前页正文（engine.fetchReadableArticle）整篇存入 ReadingListStore + toast。
/// 非浏览态无网页可抓，提示后返回。空正文由 store.add 显式抛错、提示失败。
func saveToReadingList() {
    guard isBrowsing, let engine else {
        showToast("请先打开网页", symbol: "exclamationmark.circle")
        return
    }
    showToast("正在保存到稍后读…", symbol: "text.badge.plus")
    let fullURL = engine.webView.url?.absoluteString ?? currentURL
    engine.fetchReadableArticle { [weak self] article in
        guard let self else { return }
        let item = ReadingListItem(
            title: article.title.isEmpty ? self.currentTitle : article.title,
            host: article.host.isEmpty ? self.currentURL : article.host,
            url: fullURL,
            paragraphs: article.paragraphs
        )
        do {
            try ReadingListStore.shared.add(item)
            self.showToast("已加入稍后读", symbol: "text.book.closed.fill")
        } catch {
            self.showToast("未能提取到正文，保存失败", symbol: "exclamationmark.circle")
        }
    }
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
        if currentTab == nil { newTab() }   // 没有可用标签（如刚切到无痕）
        if let t = currentTab {
            t.load(url, searchTemplate: searchTemplate)   // 本页面打开；加载遮罩避免看到旧页面
            enginePool.touch(t, current: t)
            bindActiveEngine(t)   // 跟随全局夜间/桌面开关
        }
        isBrowsing = true
        if !isIncognito { library.recordHistory(title: title ?? url, url: url) }
        scheduleTabPersist()
    }

    func goHome() {
        isBrowsing = false
        hasVideo = false   // 主页无网页视频，收起悬浮入口
    }

    /// 激活某标签引擎时统一绑定：①同步全局页面开关（夜间/桌面）②加载完成回填历史标题
    /// ③长按链接的下载 / 后台打开回调。标签激活/加载后调用——切标签、新标签都重新绑定，
    /// 避免状态与回调只挂在最初那个引擎上（切标签后失效）。
    private func bindActiveEngine(_ tab: Tab?) {
        guard let tab, !tab.isHome else { return }
        // 主动取 engine：被 LRU 回收的标签在此惰性重建并恢复会话，
        // 保证「夜间/桌面同步 + 各回调」一定绑到将要显示的这个引擎上（不会因尚未创建而漏绑）。
        let engine = tab.engine
        engine.syncPageState(night: isNightMode, desktop: isDesktopMode)
        engine.blockRedirects = blockRedirects   // 同步「拦截跳转」开关到该引擎
        engine.onBlockedRedirect = { [weak self] url in
            self?.showToast("已拦截跳转：\(url.host ?? url.absoluteString)", symbol: "hand.raised.fill")
        }
        // 应用本站已保存的广告隐藏规则（按 host 归一化匹配），随引擎激活生效。
        engine.applyAdHide(AdHideStore.shared.selectors(for: engine.webView.url?.host))
        refreshVideoPresence(for: tab)   // 切到/加载该标签时检测是否有视频
        engine.onDidFinish = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.refreshVideoPresence(for: tab)   // 加载完成后重检测视频（驱动悬浮入口显隐）
            if self.defaultVideoRate != 1.0 { tab.engine.videoSetRate(self.defaultVideoRate) }   // 应用默认倍速（无视频时为空操作）
            guard !tab.isIncognito, let pending = tab.pendingHistoryURL else { return }
            let title = tab.engine.title
            guard !title.isEmpty else { return }
            tab.pendingHistoryURL = nil
            self.library.updateHistoryTitle(url: pending, title: title)
        }
        engine.onRequestDownload = { [weak self] url in
            self?.downloadManager?.start(urlString: url.absoluteString)
            self?.showToast("开始下载…", symbol: "arrow.down.circle")
        }
        engine.onOpenInBackground = { [weak self] url in self?.openInBackground(url: url.absoluteString) }
    }

    /// 在后台新标签打开链接（不切换当前标签）
    func openInBackground(url: String) {
        let u = url.trimmingCharacters(in: .whitespaces)
        guard !u.isEmpty else { return }
        let tab = Tab(isHome: false, isIncognito: isIncognito)
        tabIndex[tab.id] = tab
        if isIncognito { incognitoTabs.append(tab) } else { tabs.append(tab) }   // 末尾
        tab.load(u, searchTemplate: searchTemplate)
        bindActiveEngine(tab)   // 后台标签也跟随全局夜间/桌面开关
        if !isIncognito { library.recordHistory(title: u, url: u) }
        bgOpenTrigger += 1   // 小动画替代提示
        scheduleTabPersist()
    }

    /// 截取当前标签缩略图（打开标签管理前调用）
    func captureCurrentThumbnail() { currentTab?.captureThumbnail() }

    /// 手势滑动切换到相邻标签（环绕），离开前先截图当前标签。
    func switchTab(by offset: Int) {
        let tabs = activeTabs
        guard tabs.count > 1, let cur = currentTab,
              let idx = tabs.firstIndex(where: { $0.id == cur.id }) else { return }
        cur.captureThumbnail()
        let next = tabs[(idx + offset + tabs.count) % tabs.count]
        select(next)
        if next.isHome { showToast("新标签页", symbol: "house") }
        else { showToast(next.displayTitle, symbol: "square.on.square") }
    }

    /// 拖动重排：把 from 移到 to 之前（当前模式的标签数组内）
    func moveTab(_ from: Tab, before to: Tab) {
        guard from.id != to.id, from.isIncognito == to.isIncognito else { return }
        if isIncognito { reorder(&incognitoTabs, from, to) } else { reorder(&tabs, from, to) }
    }
    private func reorder(_ arr: inout [Tab], _ from: Tab, _ to: Tab) {
        guard let f = arr.firstIndex(where: { $0.id == from.id }),
              let t = arr.firstIndex(where: { $0.id == to.id }) else { return }
        let item = arr.remove(at: f)
        let dest = t > f ? t - 1 : t
        arr.insert(item, at: dest)
        scheduleTabPersist()
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
            bindActiveEngine(tab)   // 切到该标签时对齐全局夜间/桌面开关
            isBrowsing = true
        }
        showTabs = false
        scheduleTabPersist()
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
        if isIncognito { incognitoTabs.append(tab) } else { tabs.append(tab) }   // 新标签在末尾
        currentTabID = tab.id
        // 设置「新标签默认打开主页」时直接加载主页地址，否则空白新标签页。
        let home = homepageURL.trimmingCharacters(in: .whitespaces)
        if newTabOpensHomepage, !home.isEmpty { open(url: home) } else { goHome() }
        pagePopTrigger += 1   // 触发新页面左下角弹出动画
        scheduleTabPersist()
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
        scheduleTabPersist()
    }

    func closeAllActive() {
        let closing = activeTabs
        for t in closing { enginePool.remove(t); tabIndex[t.id] = nil }
        withAnimation {
            if isIncognito { incognitoTabs.removeAll() } else { tabs.removeAll() }
        }
        currentTabID = nil
        isBrowsing = false
        scheduleTabPersist()
    }

    func toggleIncognito() {
        // 切换前先把当前模式的当前标签存进对应槽，切换后恢复目标模式上次的当前标签（互不干扰）。
        if isIncognito { incognitoCurrentID = currentTabID } else { normalCurrentID = currentTabID }
        withAnimation { isIncognito.toggle() }
        let restored = isIncognito ? incognitoCurrentID : normalCurrentID
        currentTabID = restored ?? activeTabs.first?.id
        if let t = currentTab, !t.isHome {
            t.activateIfNeeded(searchTemplate: searchTemplate)
            enginePool.touch(t, current: t)
            bindActiveEngine(t)
            isBrowsing = true
        } else {
            isBrowsing = false
            hasVideo = false
        }
        scheduleTabPersist()
    }
}

// MARK: - 示例数据
enum SampleData {
    static let quickLinks: [QuickLink] = [
        .init(title: "百度", url: "baidu.com", glyph: "百", colorHex: 0x2932E1),
        .init(title: "搜狗", url: "sogou.com", glyph: "搜", colorHex: 0xFB6022),
        .init(title: "Google", url: "google.com", glyph: "G", colorHex: 0x4285F4),
        .init(title: "Bing", url: "bing.com", glyph: "b", colorHex: 0x008373),
        .init(title: "神马搜索", url: "sm.cn", glyph: "神", colorHex: 0xFF7A00),
        .init(title: "360搜索", url: "so.com", glyph: "360", colorHex: 0x10B266),
        .init(title: "优酷", url: "youku.com", glyph: "优", colorHex: 0x1AA1E1),
        .init(title: "腾讯视频", url: "v.qq.com", glyph: "腾", colorHex: 0xFF9B00),
        .init(title: "微博", url: "weibo.com", glyph: "微", colorHex: 0xE6162D),
        .init(title: "网址导航", url: "hao123.com", glyph: "", colorHex: 0x0A84FF, symbol: "safari.fill"),
        .init(title: "知乎", url: "zhihu.com", glyph: "知", colorHex: 0x0066FF),
        .init(title: "B站", url: "bilibili.com", glyph: "B", colorHex: 0xFB7299),
    ]

    @MainActor static func makeTabs() -> [Tab] {
        [
            Tab(isHome: true),
            Tab(isHome: false, placeholderTitle: "天行九歌 第1集 超清HD - YouTube",
                placeholderURL: "youtube.com", tintHex: 0x4A90D9),
            Tab(isHome: false, placeholderTitle: "百度一下，你就知道",
                placeholderURL: "baidu.com", tintHex: 0x2932E1),
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

    static let history: [HistorySection] = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        let yest = f.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let old = f.string(from: Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date())
        return [
            .init(title: "今天", items: [
                .init(title: "天行九歌 第1集 - YouTube", url: "youtube.com/watch", time: "14:32", glyph: "Y", colorHex: 0xFF0000, day: today),
                .init(title: "百度一下，你就知道", url: "baidu.com", time: "13:10", glyph: "百", colorHex: 0x2932E1, day: today),
                .init(title: "GitHub: Let's build", url: "github.com", time: "11:05", glyph: "G", colorHex: 0x24292E, day: today),
            ]),
            .init(title: "昨天", items: [
                .init(title: "知乎 - 发现", url: "zhihu.com", time: "21:48", glyph: "知", colorHex: 0x0066FF, day: yest),
                .init(title: "哔哩哔哩 - 番剧", url: "bilibili.com", time: "20:12", glyph: "B", colorHex: 0xFB7299, day: yest),
            ]),
            .init(title: "更早", items: [
                .init(title: "豆瓣电影 Top250", url: "douban.com", time: "06-18", glyph: "豆", colorHex: 0x2D963D, day: old),
            ]),
        ]
    }()

}
