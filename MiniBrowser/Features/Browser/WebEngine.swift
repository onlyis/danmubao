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

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        // 注入已启用的用户脚本（必须在创建 webView 前写入 userContentController）
        let controller = WKUserContentController()
        UserScriptStore.shared.installable().forEach(controller.addUserScript)
        config.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
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
        return URL(string: searchTemplate + encoded) ?? URL(string: "https://www.bing.com")!
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
