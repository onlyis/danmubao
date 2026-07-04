import SwiftUI
import Combine

/// 全局浏览器状态。本阶段聚焦 UI 与流程，数据均为示例数据。
///
/// 主文件只保留：存储属性(@Published / let / var)、嵌套类型、静态常量、`init` 及与之紧邻的
/// 基础计算属性。其余职责按功能拆分到同目录扩展文件：
/// - `BrowserViewModel+Tabs.swift`        标签新建/关闭/切换/移动/无痕/持久化/导航动作
/// - `BrowserViewModel+Search.swift`      搜索引擎/搜索历史/联想词
/// - `BrowserViewModel+Gesture.swift`     手势匹配执行 + 工具栏自定义
/// - `BrowserViewModel+SiteSettings.swift` UA/Cookie/重定向/证书等按站设置
/// - `BrowserViewModel+Actions.swift`     菜单/控制面板的功能路由分发与各动作实现
@MainActor
final class BrowserViewModel: ObservableObject {

    // MARK: - 浏览状态
    /// 当前是否处于网页浏览态（false = 主页 / 新标签页）
    @Published var isBrowsing: Bool = false
    @Published var isIncognito: Bool = false
    /// 网页夜间模式：**仅作用于网页内容**（注入反色 CSS），不影响 App 自身外观（外观由 `appearanceMode` 决定）。持久化。
    @Published var isNightMode: Bool = false { didSet { DiskStore.save(isNightMode, to: PersistenceKey.nightMode) } }
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

    /// App 语言：跟随系统（按用户设备语言）/ 简体中文 / English。持久化。
    @Published var appLanguage: AppLanguage = .system { didSet { DiskStore.save(appLanguage, to: PersistenceKey.appLanguage) } }
    enum AppLanguage: String, CaseIterable, Identifiable, Codable {
        case system = "跟随系统", zh = "简体中文", en = "English"
        var id: String { rawValue }
        /// 生效的 Locale：system 用当前设备语言；否则强制指定。SwiftUI 的 Text/Label 按此本地化。
        var resolvedLocale: Locale {
            switch self {
            case .system: return Locale.autoupdatingCurrent
            case .zh:     return Locale(identifier: "zh-Hans")
            case .en:     return Locale(identifier: "en")
            }
        }
    }

    /// App 自身配色：夜间模式时整个 App 一并变深色（用户要「app 也要夜间」）；否则由外观模式决定。
    var resolvedScheme: ColorScheme? { isNightMode ? .dark : appearanceMode.scheme }
    /// 当前默认搜索引擎（持久化）。`searchTemplate` 由它派生，供 WebEngine.normalize 使用。
    @Published var searchEngine: SearchEngine = SearchEngine.builtIn[0] {
        didSet { DiskStore.save(searchEngine, to: PersistenceKey.searchEngine) }
    }
    /// 用户自定义搜索引擎（持久化）。
    @Published var customEngines: [SearchEngine] = [] {
        didSet { DiskStore.save(customEngines, to: PersistenceKey.customEngines) }
    }
    var searchTemplate: String { searchEngine.template }
    var allSearchEngines: [SearchEngine] { SearchEngine.builtIn + customEngines }

    /// 搜索历史（最近输入的关键词/网址，去重置顶，上限 12，持久化）。增删见 `+Search`。
    @Published var searchHistory: [String] = [] { didSet { DiskStore.save(searchHistory, to: PersistenceKey.searchHistory) } }

    /// 当前激活标签的网页引擎
    var engine: WebEngine? { currentTab?.engine }
    /// 当前页面地址 / 标题（用于网站设置、二维码等只读展示）
    var currentURL: String { currentTab?.displayURL ?? "" }
    var currentTitle: String { currentTab?.displayTitle ?? "" }
    /// 当前页完整地址（含协议与路径，供点击搜索时预填编辑）；无则回退到 host。
    var currentFullURL: String { engine?.webView.url?.absoluteString ?? currentURL }

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
        didSet { DiskStore.save(quickLinks, to: PersistenceKey.quickLinks) }
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
    var normalCurrentID: UUID?
    var incognitoCurrentID: UUID?
    /// 普通 / 无痕模式各自「当前标签」的统一读取（无论当前激活哪个模式）。
    var savedNormalID: UUID? { isIncognito ? normalCurrentID : currentTabID }
    var savedIncognitoID: UUID? { isIncognito ? currentTabID : incognitoCurrentID }

    /// id → Tab 索引，保证海量标签下 currentTab 查找为 O(1)（避免每帧线性扫描）。
    var tabIndex: [UUID: Tab] = [:]
    /// 活跃引擎 LRU 上限池：海量标签时只保留最近 N 个 WKWebView，其余回收。
    let enginePool = EnginePool()

    /// Combine 订阅容器（插件状态镜像、内容规则重载）。
    private var cancellables = Set<AnyCancellable>()
    /// 一次性标志：内容规则下次重编译完成后重载当前页（由广告/无图开关置位）。
    var reloadCurrentOnRulesChange = false

    /// 手势按钮配置（持久化）
    @Published var gesture = GestureConfig() { didSet { DiskStore.save(gesture, to: PersistenceKey.gestures) } }

    /// 底部工具栏按钮顺序（可自定义、持久化）。`.gesture` 仅在手势为「工具栏」放置时存在。
    @Published var toolbarItems: [ToolbarItemKind] = [.incognito, .search, .menu, .tabs, .home] {
        didSet { DiskStore.save(toolbarItems, to: PersistenceKey.toolbar) }
    }
    /// 旧的内置默认布局（用于一次性迁移到新默认）
    static let legacyToolbars: [[ToolbarItemKind]] = [
        [.back, .forward, .menu, .tabs, .home],
        [.night, .search, .menu, .tabs, .home],
    ]

    /// 底部主菜单的功能项（**分页**，可左右滑动；每页可长按编辑/删除/拖动/添加，持久化）。目录见 `MenuCatalog`。
    @Published var menuItems: [[String]] = MenuCatalog.defaultPages {
        didSet { DiskStore.save(menuItems, to: PersistenceKey.menu) }
    }
    /// 盾牌控制面板的快捷功能项顺序（网页相关操作，可编辑，持久化）。目录见 `ControlPanelCatalog`。
    @Published var panelItems: [String] = ControlPanelCatalog.defaultTitles {
        didSet { DiskStore.save(panelItems, to: PersistenceKey.panel) }
    }

    /// 当前页面是否检测到可播放视频（由 `WebEngine.detectVideo` 在加载完成/按需刷新）。
    /// 决定是否显示「悬浮播放」入口——没有视频就不显示，避免「有菜单没视频」。
    @Published var hasVideo: Bool = false

    /// 看图模式：当前页面提取出的图片地址
    @Published var pageImages: [String] = []
    /// 进入看图模式后是否自动进入多选态（供「批量保存图」直达 grid 选图→一键下载）。
    @Published var imageModeAutoSelect = false

    /// 网址导航分类的展开状态（默认全展开，记住用户操作并持久化）
    @Published var navExpanded: Set<String> = Set(NavCatalog.categories.map(\.title)) {
        didSet { DiskStore.save(Array(navExpanded), to: PersistenceKey.navExpanded) }
    }

    /// 新建标签时自增，触发主体页面从左下角弹出的动画（RootView 观察）
    @Published var pagePopTrigger = 0
    /// 后台打开链接时自增，触发标签按钮的小动画（替代 toast）
    @Published var bgOpenTrigger = 0

    /// 查看源码弹层
    struct SourcePreview: Identifiable { let id = UUID(); let code: String }
    @Published var sourcePreview: SourcePreview?

    init() {
        if let g = DiskStore.load(GestureConfig.self, from: PersistenceKey.gestures) { gesture = g }
        if let e = DiskStore.load(SearchEngine.self, from: PersistenceKey.searchEngine) { searchEngine = e }
        if let c = DiskStore.load([SearchEngine].self, from: PersistenceKey.customEngines) { customEngines = c }
        if let t = DiskStore.load([ToolbarItemKind].self, from: PersistenceKey.toolbar),
           !Self.legacyToolbars.contains(t) { toolbarItems = t }   // 旧默认布局迁移到新默认
        if let sh = DiskStore.load([String].self, from: PersistenceKey.searchHistory) { searchHistory = sh }
        if let ne = DiskStore.load([String].self, from: PersistenceKey.navExpanded) { navExpanded = Set(ne) }
        if let ql = DiskStore.load([QuickLink].self, from: PersistenceKey.quickLinks) { quickLinks = ql }
        if let n = DiskStore.load(Bool.self, from: PersistenceKey.nightMode) { isNightMode = n }
        if let b = DiskStore.load(Bool.self, from: PersistenceKey.blockRedirects) { blockRedirects = b }
        if let m = DiskStore.load([[String]].self, from: PersistenceKey.menu), !m.isEmpty { menuItems = m }
        if let pn = DiskStore.load([String].self, from: PersistenceKey.panel) { panelItems = pn }
        if let snd = DiskStore.load(Bool.self, from: PersistenceKey.showNavDirectory) { showNavDirectory = snd }
        if let nth = DiskStore.load(Bool.self, from: PersistenceKey.newTabOpensHomepage) { newTabOpensHomepage = nth }
        if let hu = DiskStore.load(String.self, from: PersistenceKey.homepageURL) { homepageURL = hu }
        if let dvr = DiskStore.load(Double.self, from: PersistenceKey.defaultVideoRate) { defaultVideoRate = dvr }
        if let sbt = DiskStore.load(Bool.self, from: PersistenceKey.searchBarAtTop) { searchBarAtTop = sbt }
        if let al = DiskStore.load(AppLanguage.self, from: PersistenceKey.appLanguage) { appLanguage = al }
        // 不变式校正：gesture ∈ toolbarItems ⟺ 放置方式为工具栏（防旧数据不一致导致空槽）
        let gestureInToolbar = toolbarItems.contains(.gesture)
        if (gesture.placement == .toolbar) != gestureInToolbar {
            gesture.placement = gestureInToolbar ? .toolbar : .floating
        }
        // 恢复上次的标签（普通 + 无痕都持久化）。属性观察器在 init 中不触发，恢复不会回写。
        if let state = DiskStore.load(TabsState.self, from: PersistenceKey.tabs),
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

    // MARK: - 标签持久化（合并写，避免连续增删反复整表编码）
    /// 合并落盘的延迟任务句柄（实现见 `+Tabs` 的 `scheduleTabPersist` / `persistTabsNow`）。
    var tabPersistWork: DispatchWorkItem?

    // MARK: - 分享当前页
    struct ShareItem: Identifiable { let id = UUID(); let url: URL }
    @Published var shareItem: ShareItem?

    // MARK: - 阅读模式（正文抽取）
    /// 当前抽取出的正文（标题 + 来源 host + 段落）。类型定义在 ReadingModeView.swift。
    @Published var readingArticle: ReadableArticle = .empty

    // MARK: - 二维码（生成当前页 / 识别图中码）
    /// 生成当前页二维码弹层标志（RootView 以 .sheet 呈现 QRGenerateSheet）。
    @Published var showQRGenerate = false
    /// 进入扫码页后是否自动弹出相册（供菜单「识别图中码」直达相册识别）。
    @Published var qrAutoPickPhoto = false

    // MARK: - 自动刷新（循环档位: 0=关 / 15 / 30 / 60 秒）
    /// 当前自动刷新间隔(秒), 0 表示关闭。仅作展示与档位记忆, 不持久化(刷新行为偏临时)。
    @Published var autoRefreshSeconds: Int = 0
    /// 自动刷新计时器(主线程 Timer)。开档时创建, 关档/换档时失效。
    var autoRefreshTimer: Timer?
    /// 视频自动检测计时器：浏览网页时周期性重检测页面是否有可播放视频，
    /// 让「悬浮播放」入口在视频出现/开始播放时自动显现（含 SPA 后加载的视频）。
    var videoDetectTimer: Timer?
    /// 可循环的档位序列。
    static let autoRefreshSteps: [Int] = [0, 15, 30, 60]

    // MARK: - 全屏模式（隐藏底部工具栏, 由 RootView 据此条件渲染）
    /// 是否处于全屏浏览(隐藏底部工具栏, 显示浮动退出按钮)。
    @Published var isFullScreen: Bool = false

    // MARK: - 网站设置（按当前域名）真实化
    /// User-Agent 选项标签（供网站设置 Picker 复用，单一真相源）。
    static let userAgentOptions = ["默认", "iPhone", "iPad", "Mac", "Windows"]

    // MARK: - workflow 批量功能（视频增强/AirPlay/漫画/翻译/PDF/文本/压缩）
    @Published var showAirPlay = false
    @Published var translateText: String = ""
    @Published var showTranslate: Bool = false
    struct PDFPreviewItem: Identifiable { let id = UUID(); let url: URL }
    @Published var pdfPreviewURL: PDFPreviewItem?
    @Published var textFileURL: URL?

    // MARK: - 偏好开关（外观/主页/视频，持久化）
    /// 主页第二屏「网址导航目录」是否显示（默认显示）。真实生效：HomeView 据此条件渲染第二页。
    @Published var showNavDirectory: Bool = true { didSet { DiskStore.save(showNavDirectory, to: PersistenceKey.showNavDirectory) } }
    /// 新建标签页时是否直接打开主页地址（偏好，持久化）。
    @Published var newTabOpensHomepage: Bool = false { didSet { DiskStore.save(newTabOpensHomepage, to: PersistenceKey.newTabOpensHomepage) } }
    /// 主页地址（偏好，持久化，默认百度）。
    @Published var homepageURL: String = "baidu.com" { didSet { DiskStore.save(homepageURL, to: PersistenceKey.homepageURL) } }
    /// 默认视频播放倍速（偏好，持久化，默认 1.0 倍速）。
    @Published var defaultVideoRate: Double = 1.0 { didSet { DiskStore.save(defaultVideoRate, to: PersistenceKey.defaultVideoRate) } }
    /// 搜索框位置：false = 默认在键盘上方（自定义搜索图标条的上面）；true = 固定在顶部。持久化。
    @Published var searchBarAtTop: Bool = false { didSet { DiskStore.save(searchBarAtTop, to: PersistenceKey.searchBarAtTop) } }
    /// 倍速档位（悬浮播放器倍速菜单与「倍速播放」共用），最高 7×。
    static let videoRates: [Double] = [0.5, 1.0, 1.25, 1.5, 2.0, 3.0, 5.0, 7.0]

    /// 拦截跨域自动跳转（页面级开关，按引擎生效，切标签时由 bindActiveEngine 同步）。持久化。
    @Published var blockRedirects: Bool = false { didSet { DiskStore.save(blockRedirects, to: PersistenceKey.blockRedirects) } }
    /// 证书详情 sheet 控制：非 nil 时呈现 CertificateView。
    @Published var certificateInfo: CertificateInfo?

    // MARK: - 搜索联想词（真实接口）
    /// 搜索联想词建议（来自 Bing osjson 接口，随输入实时更新；空输入时为空）
    @Published var searchSuggestions: [String] = []
    /// 当前联想词请求任务（用于防抖与取消旧请求）
    var suggestTask: Task<Void, Never>?

    // MARK: - 媒体嗅探（页面内 <video>/<audio> 地址收集 + 下载/复制/分享）
    /// 当前页面嗅探到的媒体命中（由 WebEngine.sniffMedia 填充）。
    @Published var mediaHits: [MediaHit] = []
    /// 媒体嗅探结果页呈现标志（RootView 以 .sheet 呈现 MediaSnifferView）。
    @Published var showMediaSniffer = false

    // MARK: - 视频播放异常（加载完成后自检；命中则弹「播放异常」提示，支持重试/嗅探下载）
    struct VideoAnomalyAlert: Identifiable { let id = UUID(); let text: String }
    @Published var videoAnomaly: VideoAnomalyAlert?

    // MARK: - 标签查询（O(1)）
    var activeTabs: [Tab] { isIncognito ? incognitoTabs : tabs }
    /// O(1) 查找：先走索引，命中且属当前模式则返回，否则回退到首个标签。
    var currentTab: Tab? {
        if let id = currentTabID, let t = tabIndex[id], t.isIncognito == isIncognito { return t }
        return activeTabs.first
    }
    var tabCount: Int { max(activeTabs.count, 1) }
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
        .init(title: "网址导航", url: "www.hao123.com", glyph: "", colorHex: 0x0A84FF, symbol: "safari.fill"),
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
