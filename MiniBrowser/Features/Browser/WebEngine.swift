import SwiftUI
import WebKit
import Security

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

    /// 拦截跨域自动跳转（.other 导航类型的自动重定向）。由 VM 的全局开关同步进来。
    @Published var blockRedirects = false
    /// 当前主文档 host：用于判断后续自动跳转是否跨域。didCommit 时更新。
    private var mainDocumentHost = ""
    /// 拦截到跳转时回调（携带被拦截的目标 URL），由视图层接到 Toast 提示。
    var onBlockedRedirect: ((URL) -> Void)?
    /// 最近一次 TLS 握手缓存的服务器信任对象（用于解析站点证书）。
    /// WKWebView 不直接暴露证书链，故在 `didReceive challenge` 缓存 SecTrust。
    private var latestServerTrust: SecTrust?

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

    // MARK: - 功能扩展（阅读正文/网页保存/视频循环/UA/清站数据）
/// 抽取当前页面正文（自写简化 Readability，不引三方）：
/// 优先在 article/main/[role=main] 内取，否则在常见容器候选里挑「可见文本量最大」者作正文根；
/// 收集 h1-h3 与 p，去 script/style/nav 噪音、过滤过短(<20 字)与重复段落。回调在主线程。
func fetchReadableArticle(_ completion: @escaping (ReadableArticle) -> Void) {
    let js = """
    (function(){
      // 候选正文根：语义容器优先，否则在常见块级容器里按可见文本量挑最大的
      function visText(el){ return (el && el.innerText ? el.innerText.trim().length : 0); }
      var root = document.querySelector('article')
              || document.querySelector('[role=main]')
              || document.querySelector('main');
      if (!root) {
        var best = null, bestLen = 0;
        var cands = document.querySelectorAll('article, main, section, div');
        for (var i=0;i<cands.length;i++){
          var c = cands[i];
          // 跳过明显的非正文区域
          var tag = (c.id+' '+c.className).toLowerCase();
          if (/nav|menu|header|footer|sidebar|comment|aside|ad\\b|advert/.test(tag)) continue;
          var len = visText(c);
          if (len > bestLen){ bestLen = len; best = c; }
        }
        root = best || document.body;
      }
      if (!root) return { title: document.title || '', paragraphs: [] };
      var nodes = root.querySelectorAll('h1, h2, h3, p, li, blockquote');
      var seen = {}, out = [];
      for (var j=0;j<nodes.length;j++){
        var n = nodes[j];
        // 跳过位于脚本/样式/导航内的节点
        if (n.closest('script, style, nav, header, footer, aside')) continue;
        var t = (n.innerText || '').replace(/\\s+/g, ' ').trim();
        if (t.length < 20) continue;            // 过滤过短噪音
        if (seen[t]) continue;                   // 去重
        seen[t] = 1;
        out.push(t);
        if (out.length >= 400) break;            // 上限，避免超长页卡顿
      }
      return { title: document.title || '', host: location.host || '', paragraphs: out };
    })();
    """
    webView.evaluateJavaScript(js) { result, _ in
        let dict = result as? [String: Any]
        let article = ReadableArticle(
            title: (dict?["title"] as? String) ?? "",
            host: (dict?["host"] as? String) ?? "",
            paragraphs: (dict?["paragraphs"] as? [String]) ?? []
        )
        completion(article)
    }
}
    /// 导出当前页为 WebArchive（完整离线网页存档，含资源）。
    func exportWebArchive(_ completion: @escaping (Data?) -> Void) {
        webView.createWebArchiveData { result in
            completion((try? result.get()))
        }
    }

    /// 整页长截图（含当前视口以外的内容）。
    /// WKWebView 默认只渲染可见视口，takeSnapshot 也只截可见区；要截到整页，
    /// 需临时把 webView 的 frame 撑到 scrollView.contentSize、并用覆盖整页的 rect 截图，
    /// 截完立即还原 frame 与滚动位置（避免影响正常浏览）。
    func fullPageSnapshot(_ completion: @escaping (UIImage?) -> Void) {
        let scrollView = webView.scrollView
        let fullSize = scrollView.contentSize
        guard fullSize.width > 0, fullSize.height > 0 else { completion(nil); return }

        let originalFrame = webView.frame
        let originalOffset = scrollView.contentOffset

        // 临时把 webView 铺成整页大小，让全部内容参与渲染。
        webView.frame = CGRect(origin: .zero, size: fullSize)

        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: fullSize)   // 覆盖整页，截到视口以外内容
        config.afterScreenUpdates = true

        // 等一次布局/渲染刷新后再截图，确保撑开后的内容已绘制。
        DispatchQueue.main.async { [weak self] in
            guard let self else { completion(nil); return }
            self.webView.takeSnapshot(with: config) { image, _ in
                // 还原 frame 与滚动位置。
                self.webView.frame = originalFrame
                scrollView.contentOffset = originalOffset
                completion(image)
            }
        }
    }
    /// 切换页面首个有效 <video> 的循环播放(单曲循环)。
    /// 回传新的 loop 状态; 页面无 <video> 时回传 nil(供上层提示「未检测到视频」)。
    func videoToggleLoop(completion: @escaping (Bool?) -> Void) {
        let js = videoScript("v.loop=!v.loop;return v.loop;")
        webView.evaluateJavaScript(js) { result, _ in
            Task { @MainActor in completion(result as? Bool) }
        }
    }
/// 设置自定义 User-Agent（nil 恢复系统默认）并重载生效。
func setUserAgent(_ ua: String?) {
    webView.customUserAgent = ua
    // 标记桌面态以便切标签同步时不被 syncPageState 覆盖（Mac/Windows UA 视为桌面）。
    desktopMode = (ua != nil && ua == desktopUA)
    webView.reload()
}

/// 清除指定 host 的网站数据（Cookie / 缓存 / 本地存储等）。
/// 使用本引擎自己的 websiteDataStore（无痕引擎为内存态隔离存储），异步完成后回主线程回调。
func clearSiteData(host: String, completion: @escaping () -> Void) {
    let store = webView.configuration.websiteDataStore
    let types = WKWebsiteDataStore.allWebsiteDataTypes()
    store.fetchDataRecords(ofTypes: types) { records in
        // host 可能是裸域名（如 example.com），记录的 displayName 多为域名后缀；用包含匹配兜底子域。
        let targets = records.filter { record in
            let name = record.displayName
            return host == name || host.hasSuffix(name) || name.hasSuffix(host)
        }
        let toRemove = targets.isEmpty ? records.filter { host.contains($0.displayName) } : targets
        store.removeData(ofTypes: types, for: toRemove) {
            // removeData 完成回调不保证在主线程：显式回主线程。
            Task { @MainActor in completion() }
        }
    }
}

    // MARK: - 视频增强 / 开发者控制台 / 整页文本（workflow 集成）
    func videoCaptureFrame(completion: @escaping (UIImage?) -> Void) {
        let js = videoScript("""
        try {
          var w = v.videoWidth || v.clientWidth, h = v.videoHeight || v.clientHeight;
          if (!w || !h) return null;
          var c = document.createElement('canvas'); c.width = w; c.height = h;
          c.getContext('2d').drawImage(v, 0, 0, w, h);
          return c.toDataURL('image/png');
        } catch (e) { return null; }
        """)
        webView.evaluateJavaScript(js) { result, _ in
            guard let dataURL = result as? String, let comma = dataURL.firstIndex(of: ","),
                  let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
                  let image = UIImage(data: data) else { completion(nil); return }
            completion(image)
        }
    }
    func videoToggleMirror(completion: @escaping (Bool?) -> Void) {
        let js = videoScript("""
        var t = (v.style.transform || ''); var has = t.indexOf('scaleX(-1)') !== -1;
        if (has) { v.style.transform = t.replace('scaleX(-1)', '').trim(); return false; }
        else { v.style.transform = (t + ' scaleX(-1)').trim(); return true; }
        """)
        webView.evaluateJavaScript(js) { result, _ in Task { @MainActor in completion(result as? Bool) } }
    }
    /// 开启后台播放：AVFoundation 依赖隔离在 BackgroundAudio（独立文件）。
    func enableBackgroundPlayback() throws { try BackgroundAudio.enable() }

    /// 可注入的移动端调试控制台类型。
    enum DevConsole {
        case eruda, vconsole
        var src: String { self == .eruda ? "https://cdn.jsdelivr.net/npm/eruda" : "https://cdn.jsdelivr.net/npm/vconsole@latest/dist/vconsole.min.js" }
        var initCall: String { self == .eruda ? "if(window.eruda){eruda.init();}" : "if(window.VConsole){window.__mb_vconsole=new window.VConsole();}" }
        var flagID: String { self == .eruda ? "__mb_eruda" : "__mb_vconsole_loader" }
    }
    /// 向当前页注入调试控制台（CDN 动态加载, 幂等）。
    func injectDevConsole(_ kind: DevConsole) {
        let js = """
        (function(){
          if (document.getElementById('\(kind.flagID)')) { \(kind.initCall) return; }
          var s = document.createElement('script'); s.id='\(kind.flagID)'; s.src='\(kind.src)';
          s.onload = function(){ \(kind.initCall) };
          (document.head || document.documentElement).appendChild(s);
        })();
        """
        webView.evaluateJavaScript(js)
    }
    /// 抓取页面主要可见文本（整页翻译用）。
    func fetchPageText(_ completion: @escaping (String?) -> Void) {
        let js = """
        (function(){
          var root = document.querySelector('article') || document.querySelector('[role=main]')
                  || document.querySelector('main') || document.body;
          var t = (root && root.innerText ? root.innerText : (document.body ? document.body.innerText : ''));
          return (t || '').replace(/\\n{3,}/g, '\\n\\n').trim().slice(0, 4000);
        })();
        """
        webView.evaluateJavaScript(js) { r, _ in completion(r as? String) }
    }

// MARK: - 标记广告：元素拾取 + 按站隐藏 CSS 注入
// 持有当前已隐藏选择器，didFinish（导航/重载后）按本站重注入，做到持续生效且不依赖外部传 host。
// 注：以下属性与方法均加在 WebEngine 类体内（@MainActor）。

/// 本站当前生效的隐藏选择器（applyAdHide 时记下）。didFinish 后非空则重注入。
private(set) var adHideSelectors: [String] = []

/// 元素拾取轮询定时器与回调（取回选择器即回调上层去持久化+隐藏）。
private var elementPickTimer: Timer?
private var onElementPicked: ((String) -> Void)?

/// 进入元素拾取态：注入一个置顶高亮层，跟随触摸高亮命中元素、点触确认时把其 CSS 选择器写入
/// window.__mb_pick_selector；Swift 端用 Timer 轮询取回（WKWebView 无法直接同步回传，故走轮询范式）。
func beginElementPick(onPick: @escaping (String) -> Void) {
    onElementPicked = onPick
    let js = """
    (function(){
      if (window.__mb_pickActive) { return; }
      window.__mb_pickActive = true;
      window.__mb_pick_selector = '';
      // 计算一个尽量唯一且稳定的 CSS 选择器：优先 #id，否则用「tag.class:nth-of-type」逐级上溯（最多 4 级）。
      function cssPath(el){
        if (!el || el.nodeType !== 1) return '';
        if (el.id) { return '#' + CSS.escape(el.id); }
        var parts = [];
        var node = el, depth = 0;
        while (node && node.nodeType === 1 && node !== document.body && depth < 4){
          var seg = node.tagName.toLowerCase();
          var cls = (node.className && typeof node.className === 'string')
            ? node.className.trim().split(/\\s+/).filter(Boolean).slice(0,2) : [];
          for (var i=0;i<cls.length;i++){ seg += '.' + CSS.escape(cls[i]); }
          var p = node.parentNode;
          if (p){
            var same = [], k;
            for (k=0;k<p.children.length;k++){ if (p.children[k].tagName === node.tagName) same.push(p.children[k]); }
            if (same.length > 1){ seg += ':nth-of-type(' + (Array.prototype.indexOf.call(p.children, node)+1) + ')'; }
          }
          parts.unshift(seg);
          if (node.id){ parts[0] = '#' + CSS.escape(node.id); break; }
          node = node.parentNode; depth++;
        }
        return parts.join(' > ');
      }
      // 高亮浮层。
      var hi = document.createElement('div');
      hi.id = '__mb_pick_highlight';
      hi.style.cssText = 'position:fixed;z-index:2147483646;pointer-events:none;border:2px solid #FF3B30;background:rgba(255,59,48,0.18);box-sizing:border-box;border-radius:4px;display:none;left:0;top:0;';
      document.documentElement.appendChild(hi);
      function topElementAt(x,y){
        hi.style.display='none';
        var el = document.elementFromPoint(x,y);
        hi.style.display='block';
        return el;
      }
      function moveTo(el){
        if (!el || el === hi){ hi.style.display='none'; return; }
        var r = el.getBoundingClientRect();
        hi.style.display='block';
        hi.style.left = r.left + 'px'; hi.style.top = r.top + 'px';
        hi.style.width = r.width + 'px'; hi.style.height = r.height + 'px';
      }
      function onMove(e){
        var t = (e.touches && e.touches[0]) ? e.touches[0] : e;
        moveTo(topElementAt(t.clientX, t.clientY));
      }
      function onPick(e){
        var t = (e.changedTouches && e.changedTouches[0]) ? e.changedTouches[0] : e;
        var el = topElementAt(t.clientX, t.clientY);
        if (el && el !== hi){
          var sel = cssPath(el);
          if (sel){ window.__mb_pick_selector = sel; }
        }
        e.preventDefault(); e.stopPropagation();
      }
      window.__mb_pick_handlers = { onMove: onMove, onPick: onPick, hi: hi };
      document.addEventListener('mousemove', onMove, true);
      document.addEventListener('touchmove', onMove, true);
      document.addEventListener('click', onPick, true);
      document.addEventListener('touchend', onPick, true);
    })();
    """
    webView.evaluateJavaScript(js)
    // 轮询取回选中的选择器（每 0.2s 一次）；取到后清空 JS 侧标记，回调上层。
    elementPickTimer?.invalidate()
    elementPickTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
        guard let self else { return }
        self.webView.evaluateJavaScript("(function(){var s=window.__mb_pick_selector||'';window.__mb_pick_selector='';return s;})();") { result, _ in
            guard let sel = result as? String, !sel.isEmpty else { return }
            self.onElementPicked?(sel)
        }
    }
}

/// 退出元素拾取态：停止轮询、移除监听层与高亮浮层（已隐藏的元素保持隐藏）。
func cancelElementPick() {
    elementPickTimer?.invalidate()
    elementPickTimer = nil
    onElementPicked = nil
    let js = """
    (function(){
      var h = window.__mb_pick_handlers;
      if (h){
        document.removeEventListener('mousemove', h.onMove, true);
        document.removeEventListener('touchmove', h.onMove, true);
        document.removeEventListener('click', h.onPick, true);
        document.removeEventListener('touchend', h.onPick, true);
        if (h.hi && h.hi.parentNode){ h.hi.parentNode.removeChild(h.hi); }
      }
      window.__mb_pickActive = false;
      window.__mb_pick_handlers = null;
      window.__mb_pick_selector = '';
    })();
    """
    webView.evaluateJavaScript(js)
}

/// 注入/更新本站隐藏 CSS（id=__mb_adhide 的 <style>，display:none!important）。
/// 空列表则移除该 style。记下 selectors 供 didFinish 后重注入。
func applyAdHide(_ selectors: [String]) {
    adHideSelectors = selectors
    injectAdHideCSS()
}

/// 按 adHideSelectors 注入或移除隐藏样式（导航后 document 丢失，需重注入）。
private func injectAdHideCSS() {
    guard !adHideSelectors.isEmpty else {
        webView.evaluateJavaScript("var s=document.getElementById('__mb_adhide');if(s)s.remove();")
        return
    }
    // 把选择器拼成一条 CSS 规则；选择器内含的反斜杠/引号经 JSON 编码转义后安全嵌入 JS 字符串。
    let rule = adHideSelectors.joined(separator: ",") + "{display:none!important}"
    let literal: String = {
        guard let data = try? JSONEncoder().encode(rule) else { return "\"\"" }
        return String(decoding: data, as: UTF8.self)
    }()
    let js = "var s=document.getElementById('__mb_adhide');if(!s){s=document.createElement('style');s.id='__mb_adhide';(document.head||document.documentElement).appendChild(s);}s.innerHTML=\(literal);"
    webView.evaluateJavaScript(js)
}

    // MARK: - 站点证书：解析最近缓存的 SecTrust（仅用 iOS 可用 API）
    func certificateInfo(host: String) -> CertificateInfo? {
        guard let trust = latestServerTrust else { return nil }
        let chain: [SecCertificate]
        if #available(iOS 15.0, *) {
            chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        } else {
            var arr: [SecCertificate] = []
            for i in 0..<SecTrustGetCertificateCount(trust) {
                if let c = SecTrustGetCertificateAtIndex(trust, i) { arr.append(c) }
            }
            chain = arr
        }
        guard let leaf = chain.first else { return nil }
        let subject = (SecCertificateCopySubjectSummary(leaf) as String?) ?? "未知"
        // iOS 不暴露 SecCertificateCopyValues：用证书链上一级主体摘要近似「颁发者」。
        let issuer = chain.count > 1 ? ((SecCertificateCopySubjectSummary(chain[1]) as String?) ?? "未知") : "未知"
        return CertificateInfo(host: host, subjectSummary: subject, issuerSummary: issuer,
                               notBefore: nil, notAfter: nil, serialNumber: "", chainLength: chain.count)
    }

    /// 嗅探页面内全部 <video>/<audio>（含其 <source> 子节点）的可下载地址。
    /// 仅收集 http(s)，按地址去重；标题取最近标题/aria-label 或文件名兜底。回调在主线程。
    func sniffMedia(_ completion: @escaping ([MediaHit]) -> Void) {
        let js = """
        (function(){
          var out = [];
          // 取一个可读标题：优先 title/aria-label，否则向上找最近标题文本，最后回退到文件名。
          function readableTitle(el, src){
            var t = (el.getAttribute('title') || el.getAttribute('aria-label') || '').trim();
            if (t) return t;
            var node = el, depth = 0;
            while (node && depth < 5){
              var h = node.querySelector ? node.querySelector('h1,h2,h3,figcaption') : null;
              if (h && h.innerText && h.innerText.trim()) return h.innerText.trim().slice(0,80);
              node = node.parentElement; depth++;
            }
            try {
              var u = new URL(src, location.href);
              var last = u.pathname.split('/').filter(Boolean).pop();
              if (last) return decodeURIComponent(last);
            } catch(e){}
            return src;
          }
          function add(src, kind, el){
            if (!src) return;
            // 仅收集 http(s)（排除 blob:/data:/相对资源）。
            if (src.indexOf('http') !== 0) return;
            out.push({ url: src, kind: kind, title: readableTitle(el, src) });
          }
          ['video','audio'].forEach(function(tag){
            var els = document.getElementsByTagName(tag);
            for (var i=0;i<els.length;i++){
              var el = els[i];
              add(el.currentSrc || el.src || '', tag, el);
              var sources = el.getElementsByTagName('source');
              for (var j=0;j<sources.length;j++){
                add(sources[j].src || sources[j].getAttribute('src') || '', tag, el);
              }
            }
          });
          // 按 url 去重，保留首次出现。
          var seen = {}, dedup = [];
          for (var k=0;k<out.length;k++){
            var u = out[k].url;
            if (seen[u]) continue;
            seen[u] = 1;
            dedup.push(out[k]);
          }
          return dedup.slice(0, 200);
        })();
        """
        webView.evaluateJavaScript(js) { result, _ in
            let raw = (result as? [[String: Any]]) ?? []
            let hits: [MediaHit] = raw.compactMap { item in
                guard let url = item["url"] as? String, !url.isEmpty else { return nil }
                let kind: MediaHit.Kind = (item["kind"] as? String) == "audio" ? .audio : .video
                let title = (item["title"] as? String).map { $0.isEmpty ? url : $0 } ?? url
                return MediaHit(url: url, kind: kind, title: title)
            }
            // evaluateJavaScript 回调在主线程派发；本类方法为 @MainActor，直接回调。
            completion(hits)
        }
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
        if let host = webView.url?.host, !host.isEmpty { mainDocumentHost = host }   // 记录主文档域名，供跨域跳转判断
    }

    /// 拦截跳转：开启 blockRedirects 时，取消「跨域 + .other（无用户点击）」的自动重定向。
    /// 用户点击链接(.linkActivated)、表单提交、前进后退等正常导航不受影响。
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard blockRedirects, navigationAction.navigationType == .other,
              let target = navigationAction.request.url, let targetHost = target.host,
              !mainDocumentHost.isEmpty, targetHost != mainDocumentHost else {
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
        onBlockedRedirect?(target)
    }

    /// 缓存服务器信任对象用于证书查看；信任决策仍交回系统默认处理（不改变安全行为）。
    func webView(_ webView: WKWebView,
                 didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            latestServerTrust = trust
        }
        completionHandler(.performDefaultHandling, nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false; navigating = false
        if nightMode { injectNightCSS() }   // 导航后 document 丢失反色样式，重注入以保持夜间
        if !adHideSelectors.isEmpty { injectAdHideCSS() }   // 导航后按本站重注入广告隐藏 CSS，持续生效
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
