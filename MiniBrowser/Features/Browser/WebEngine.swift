import SwiftUI
import WebKit
import Security

/// 真实网页引擎：封装 WKWebView，向 UI 暴露标题、进度、前进/后退等状态。
///
/// 本文件只承载存储属性 / init / SwiftUI 桥接；行为按职责拆到同目录扩展：
/// - `WebEngine+Navigation.swift`：导航控制 + WKNavigationDelegate / WKUIDelegate + 网站设置联动 + 输入归一化
/// - `WebEngine+JS.swift`：各类 JS 注入与执行（阅读模式 / 图片提取 / 视频检测 / 媒体嗅探 / 夜间 / 广告隐藏 等）
/// - `WebEngine+Observers.swift`：KVO（progress/title/url/canGo*）+ 站点证书 SecTrust 解析
@MainActor
final class WebEngine: NSObject, ObservableObject {
    let webView: WKWebView

    @Published var displayURL = ""      // 地址栏展示（host 优先）
    @Published var title = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var progress: Double = 0
    @Published var isLoading = false
    /// 显式加载新地址期间为 true（遮住旧页面，避免切换时看到上一个页面）；首帧提交后清除。
    @Published var navigating = false
    /// 页面加载失败信息（非空时在内容区展示错误页，而非停留在上一页内容）。
    @Published var loadError: LoadError?
    struct LoadError: Equatable { var url: String; var message: String; var code: Int }
    /// 顶部地址栏是否随滚动隐藏（下滑隐藏、上滑或回到顶部时显示）。由 scrollView 偏移驱动。
    @Published var chromeHidden = false
    /// 上一次用于判定滚动方向的纵向偏移（越过阈值才更新，实现累积判向）。
    var lastScrollY: CGFloat = 0

    /// 桌面版 UA（Safari on macOS）
    let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    var observations: [NSKeyValueObservation] = []

    /// 页面级状态（夜间 / 桌面版）——每个引擎各自持有。
    /// 夜间靠注入 CSS，页面导航会丢失，故 `didFinish` 后按此标志重注入；
    /// 切换标签时由 `syncPageState` 把全局开关同步进来，避免新引擎与全局开关脱节。
    var nightMode = false
    var desktopMode = false

    /// 拦截跨域自动跳转（.other 导航类型的自动重定向）。由 VM 的全局开关同步进来。
    @Published var blockRedirects = false
    /// 当前主文档 host：用于判断后续自动跳转是否跨域。didCommit 时更新。
    var mainDocumentHost = ""
    /// 已用 www. 重试过的 host（避免裸域名证书/连接失败时无限重试）；成功提交后清空。
    var wwwRetriedHost: String?
    /// 最近一次 load 的目标 URL（证书失败改用 www. 重试时据此重建带 www 的地址）。
    var pendingLoadURL: URL?
    /// 拦截到跳转时回调（携带被拦截的目标 URL），由视图层接到 Toast 提示。
    var onBlockedRedirect: ((URL) -> Void)?
    /// 最近一次 TLS 握手缓存的服务器信任对象（用于解析站点证书）。
    /// WKWebView 不直接暴露证书链，故在 `didReceive challenge` 缓存 SecTrust。
    var latestServerTrust: SecTrust?

    /// 长按链接时通过原生上下文菜单请求下载（由视图层接到 DownloadManager）。
    var onRequestDownload: ((URL) -> Void)?
    /// 长按链接「在后台打开」回调。
    var onOpenInBackground: ((URL) -> Void)?
    /// 长按链接「在新标签页打开」回调（前台新建并切换过去）。
    var onOpenInNewTab: ((URL) -> Void)?
    /// 长按图片「批量保存图片」回调（进入看图模式多选态一键下载）。
    var onBatchSaveImages: (() -> Void)?
    /// 页面加载完成回调（用于回填历史标题等）。
    var onDidFinish: (() -> Void)?

    /// 本站当前生效的隐藏选择器（applyAdHide 时记下）。didFinish 后非空则重注入。
    var adHideSelectors: [String] = []
    /// 元素拾取轮询定时器与回调（取回选择器即回调上层去持久化+隐藏）。
    var elementPickTimer: Timer?
    var onElementPicked: ((String) -> Void)?

    /// 会话状态：完整的前进/后退列表 + 当前页 + 滚动位置（`WKWebView.interactionState`, iOS 15+）。
    /// 用于引擎被 LRU 池回收后重建时无损恢复——避免丢失历史或从头加载页面。
    var sessionState: Data? {
        get { webView.interactionState as? Data }
        set { if let newValue { webView.interactionState = newValue } }
    }

    /// 全体无痕标签共享的临时数据存储：cookie/缓存仅存内存，与普通浏览隔离，App 退出即清空。
    /// 无痕标签的「列表」仍会持久化（见 TabsState），但其会话/cookie 不落盘——这才是真正的无痕。
    private static let incognitoDataStore = WKWebsiteDataStore.nonPersistent()

    init(incognito: Bool = false) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true   // 悬浮播放：视频整体画中画浮出
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        if incognito { config.websiteDataStore = Self.incognitoDataStore }   // cookie 与普通模式隔离
        // 注入用户脚本 + 插件（必须在创建 webView 前写入 userContentController）
        let controller = WKUserContentController()
        UserScriptStore.shared.installable().forEach(controller.addUserScript)
        PluginStore.shared.installableUserScripts().forEach(controller.addUserScript)
        PluginStore.shared.compiledRuleLists.forEach(controller.add)   // 广告拦截等内容规则
        config.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isFindInteractionEnabled = true   // 系统页面查找栏（含匹配计数/上下一个）
        setupObservers()
    }
}

/// 将 WKWebView 桥接进 SwiftUI
struct WebViewContainer: UIViewRepresentable {
    @ObservedObject var engine: WebEngine
    func makeUIView(context: Context) -> WKWebView { engine.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // 显式加载新地址期间隐藏 webView，避免看到旧页面（与 BrowserView 的遮罩双保险）
        uiView.alpha = engine.navigating ? 0 : 1
    }
}
