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

    /// 桌面版 UA（Safari on macOS）
    private let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private var observations: [NSKeyValueObservation] = []

    /// 长按链接时通过原生上下文菜单请求下载（由视图层接到 DownloadManager）。
    var onRequestDownload: ((URL) -> Void)?

    /// 会话状态：完整的前进/后退列表 + 当前页 + 滚动位置（`WKWebView.interactionState`, iOS 15+）。
    /// 用于引擎被 LRU 池回收后重建时无损恢复——避免丢失历史或从头加载页面。
    var sessionState: Data? {
        get { webView.interactionState as? Data }
        set { if let newValue { webView.interactionState = newValue } }
    }

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
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
        func bind<T>(_ keyPath: KeyPath<WKWebView, T>, _ apply: @escaping (WKWebView) -> Void) -> NSKeyValueObservation {
            webView.observe(keyPath, options: [.new]) { wv, _ in
                Task { @MainActor in apply(wv) }
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
    func load(_ url: URL) { webView.load(URLRequest(url: url)) }
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
    func setDesktop(_ on: Bool) {
        webView.customUserAgent = on ? desktopUA : nil
        webView.reload()
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

    func applyNight(_ on: Bool) {
        let js = on
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
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }
}

extension WebEngine: WKUIDelegate {
    /// 长按链接：在系统默认菜单基础上追加「下载链接」。非链接（图片/纯文本/空白）不接管，交回系统默认行为。
    func webView(_ webView: WKWebView,
                 contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
                 completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
        guard let url = elementInfo.linkURL else { completionHandler(nil); return }
        let config = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] suggested in
            let download = UIAction(title: "下载链接",
                                    image: UIImage(systemName: "arrow.down.circle")) { _ in
                self?.onRequestDownload?(url)
            }
            return UIMenu(title: url.absoluteString, children: suggested + [download])
        }
        completionHandler(config)
    }
}

/// 将 WKWebView 桥接进 SwiftUI
struct WebViewContainer: UIViewRepresentable {
    let engine: WebEngine
    func makeUIView(context: Context) -> WKWebView { engine.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
