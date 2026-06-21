import SwiftUI
import WebKit

/// 真实网页引擎：封装 WKWebView，向 UI 暴露标题、进度、前进/后退等状态。
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

    /// 桌面版 UA（Safari on macOS）
    private let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private var observations: [NSKeyValueObservation] = []

    /// 页面级状态（夜间 / 桌面版）——每个引擎各自持有。
    /// 夜间靠注入 CSS，页面导航会丢失，故 `didFinish` 后按此标志重注入；
    /// 切换标签时由 `syncPageState` 把全局开关同步进来，避免新引擎与全局开关脱节。
    private(set) var nightMode = false
    private(set) var desktopMode = false

    /// 长按链接时通过原生上下文菜单请求下载（由视图层接到 DownloadManager）。
    var onRequestDownload: ((URL) -> Void)?
    /// 长按链接「在后台打开」回调。
    var onOpenInBackground: ((URL) -> Void)?
    /// 页面加载完成回调（用于回填历史标题等）。
    var onDidFinish: (() -> Void)?

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

    private func setupObservers() {
        func bind<T>(_ keyPath: KeyPath<WKWebView, T>, _ apply: @escaping @MainActor (WKWebView) -> Void) -> NSKeyValueObservation {
            webView.observe(keyPath, options: [.new]) { wv, _ in
                // WKWebView 的 KVO 通知本就在主线程派发：直接同步执行，省掉每次进度更新的 Task 调度开销。
                // 兜底——万一不在主线程，回主线程异步执行。
                if Thread.isMainThread { MainActor.assumeIsolated { apply(wv) } }
                else { Task { @MainActor in apply(wv) } }
            }
        }
        observations = [
            bind(\.estimatedProgress) { [weak self] wv in self?.progress = wv.estimatedProgress },
            bind(\.title) { [weak self] wv in if let t = wv.title, !t.isEmpty { self?.title = t } },
            bind(\.url) { [weak self] wv in self?.displayURL = wv.url?.host ?? wv.url?.absoluteString ?? "" },
            bind(\.canGoBack) { [weak self] wv in self?.canGoBack = wv.canGoBack },
            bind(\.canGoForward) { [weak self] wv in self?.canGoForward = wv.canGoForward },
        ]
    }

    // MARK: - 导航
    func submit(_ text: String, searchTemplate: String) {
        load(Self.normalize(text, searchTemplate: searchTemplate))
    }
    func load(_ url: URL) { navigating = true; webView.load(URLRequest(url: url)) }
    /// 重新套用当前所有启用的内容拦截规则（插件启停后调用），可选随即重载当前页使其立即生效。
    func refreshContentRules(reload: Bool) {
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        PluginStore.shared.compiledRuleLists.forEach(controller.add)
        if reload { webView.reload() }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stop() { webView.stopLoading() }

    // MARK: - 网站设置联动
    /// 切换桌面版：改 UA。`reload` 默认 true（用户主动切换需重排版生效）；
    /// 切标签同步时传 false，只对齐 UA 不触发重载。
    func setDesktop(_ on: Bool, reload: Bool = true) {
        desktopMode = on
        webView.customUserAgent = on ? desktopUA : nil
        if reload { webView.reload() }
    }

    /// 标签激活时把全局页面状态同步进本引擎：夜间立即注入（无重载、幂等），桌面仅对齐 UA。
    func syncPageState(night: Bool, desktop: Bool) {
        applyNight(night)
        if desktop != desktopMode { setDesktop(desktop, reload: false) }
    }

    /// 提取当前页面中的图片地址（去重，仅 http(s)）
    func fetchImageURLs(_ completion: @escaping ([String]) -> Void) {
        let js = """
        (function(){
          var urls = [];
          document.querySelectorAll('img').forEach(function(img){
            var s = img.currentSrc || img.src;
            if (s && s.indexOf('http') === 0) urls.push(s);
          });
          return Array.from(new Set(urls)).slice(0, 120);
        })();
        """
        webView.evaluateJavaScript(js) { result, _ in
            completion((result as? [String]) ?? [])
        }
    }

    /// 导出当前页为 PDF。
    func exportPDF(_ completion: @escaping (Data?) -> Void) {
        webView.createPDF { result in
            completion((try? result.get()))
        }
    }

    /// 读取当前页完整 HTML 源码。
    func fetchHTML(_ completion: @escaping (String?) -> Void) {
        webView.evaluateJavaScript("document.documentElement.outerHTML") { r, _ in
            completion(r as? String)
        }
    }

    /// 截取当前页缩略图（降采样到 300pt 宽，省内存），用于标签卡片。
    func snapshot(_ completion: @escaping (UIImage?) -> Void) {
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 300
        webView.takeSnapshot(with: config) { image, _ in completion(image) }
    }

    /// 调起系统页面查找栏。
    func presentFind() {
        webView.findInteraction?.presentFindNavigator(showingReplace: false)
    }

    /// 调起系统打印面板。
    func printPage(jobName: String) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = jobName.isEmpty ? "网页" : jobName
        controller.printInfo = info
        controller.printFormatter = webView.viewPrintFormatter()
        controller.present(animated: true, completionHandler: nil)
    }

    /// 读取页面当前选中的文本（用于划词浮层）；无选中返回空串。
    func fetchSelectedText(_ completion: @escaping (String) -> Void) {
        webView.evaluateJavaScript("window.getSelection().toString()") { result, _ in
            completion((result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        }
    }

    // MARK: - 视频检测与控制（悬浮播放器直接驱动页面里的真实 <video>）
    /// 页面是否存在「可播放、可见」的视频（有 src/source 且尺寸 > 0）。
    func detectVideo(_ completion: @escaping (Bool) -> Void) {
        let js = """
        (function(){
          var vs = document.getElementsByTagName('video');
          for (var i=0;i<vs.length;i++){
            var v = vs[i], r = v.getBoundingClientRect();
            if ((v.currentSrc || v.src || v.querySelector('source')) && r.width>1 && r.height>1) return true;
          }
          return false;
        })();
        """
        webView.evaluateJavaScript(js) { result, _ in completion((result as? Bool) ?? false) }
    }

    /// 对页面首个有效 <video> 执行一段脚本（player 控制）。
    private func videoScript(_ body: String) -> String {
        "(function(){var v=document.querySelector('video');if(!v)return null;\(body)})();"
    }
    func videoTogglePlay() { webView.evaluateJavaScript(videoScript("if(v.paused){v.play()}else{v.pause()}")) }
    func videoSetRate(_ rate: Double) { webView.evaluateJavaScript(videoScript("v.playbackRate=\(rate);")) }
    func videoSeek(by seconds: Double) { webView.evaluateJavaScript(videoScript("v.currentTime=Math.max(0,(v.currentTime||0)+(\(seconds)));")) }
    func videoRequestPiP() {
        // 调起 WKWebView 内置的画中画（需页面视频支持）。
        webView.evaluateJavaScript(videoScript("if(v.webkitSupportsPresentationMode&&v.webkitSetPresentationMode){v.webkitSetPresentationMode('picture-in-picture')}else if(v.requestPictureInPicture){v.requestPictureInPicture()}"))
    }

    /// 当前视频播放状态（用于悬浮播放器显示真实进度/倍速）。
    struct VideoState { var current: Double; var duration: Double; var paused: Bool; var rate: Double }
    func fetchVideoState(_ completion: @escaping (VideoState?) -> Void) {
        let js = videoScript("return {c:v.currentTime||0,d:isFinite(v.duration)?v.duration:0,p:v.paused,r:v.playbackRate||1};")
        webView.evaluateJavaScript(js) { result, _ in
            guard let d = result as? [String: Any] else { completion(nil); return }
            completion(VideoState(current: d["c"] as? Double ?? 0,
                                  duration: d["d"] as? Double ?? 0,
                                  paused: d["p"] as? Bool ?? true,
                                  rate: d["r"] as? Double ?? 1))
        }
    }

    func applyNight(_ on: Bool) {
        nightMode = on
        injectNightCSS()
    }

    /// 按 `nightMode` 注入或移除反色样式（导航后 document 会丢失，需重注入）。
    private func injectNightCSS() {
        let js = nightMode
        ? "var s=document.getElementById('__mb_night');if(!s){s=document.createElement('style');s.id='__mb_night';document.head.appendChild(s);}s.innerHTML='html{filter:invert(1) hue-rotate(180deg)!important;background:#111!important}img,video,picture,svg,canvas{filter:invert(1) hue-rotate(180deg)!important}';"
        : "var s=document.getElementById('__mb_night');if(s)s.remove();"
        webView.evaluateJavaScript(js)
    }

    // MARK: - 输入归一化：网址 or 搜索关键词
    static func normalize(_ text: String, searchTemplate: String) -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let looksLikeURL = !trimmed.contains(" ") && trimmed.contains(".")
        if looksLikeURL {
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
               let u = URL(string: trimmed) { return u }
            if let u = URL(string: "https://" + trimmed) { return u }
        }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        // 模板含 %s 则替换，否则把关键词追加到末尾（兼容内置与自定义引擎两种写法）。
        let urlStr = searchTemplate.contains("%s")
            ? searchTemplate.replacingOccurrences(of: "%s", with: encoded)
            : searchTemplate + encoded
        return URL(string: urlStr) ?? URL(string: "https://www.bing.com")!
    }
}

extension WebEngine: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        navigating = false   // 新页面首帧已就绪，撤掉加载遮罩
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false; navigating = false
        if nightMode { injectNightCSS() }   // 导航后 document 丢失反色样式，重注入以保持夜间
        onDidFinish?()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false; navigating = false
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false; navigating = false
    }
}

extension WebEngine: WKUIDelegate {
    /// 长按链接：在系统默认菜单基础上追加「下载链接」。非链接（图片/纯文本/空白）不接管，交回系统默认行为。
    func webView(_ webView: WKWebView,
                 contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
                 completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
        // 链接：追加自定义动作；图片等其它元素：保留系统默认菜单（保存图片/拷贝等）
        let url = elementInfo.linkURL
        let config = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] suggested in
            guard let url else { return UIMenu(title: "", children: suggested) }
            let background = UIAction(title: "在后台打开",
                                      image: UIImage(systemName: "rectangle.stack.badge.plus")) { _ in
                self?.onOpenInBackground?(url)
            }
            let download = UIAction(title: "下载链接",
                                    image: UIImage(systemName: "arrow.down.circle")) { _ in
                self?.onRequestDownload?(url)
            }
            return UIMenu(title: url.absoluteString, children: suggested + [background, download])
        }
        completionHandler(config)
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
