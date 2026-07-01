import SwiftUI
import WebKit

/// WebEngine 导航职责：地址加载 / 前进后退 / 内容规则刷新 / 网站设置联动（桌面版·UA·清站数据）/
/// 输入归一化，以及 WKNavigationDelegate、WKUIDelegate（含长按链接下载/后台打开菜单）协议遵从。
extension WebEngine {
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

    // MARK: - 输入归一化：网址 or 搜索关键词
    static func normalize(_ text: String, searchTemplate: String) -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let looksLikeURL = !trimmed.contains(" ") && trimmed.contains(".")
        // 形如网址：交给 String.asWebURL() 统一补协议并构造（http(s) 原样、否则补 https://）。
        if looksLikeURL, let u = trimmed.asWebURL() { return u }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        // 模板含 %s 则替换，否则把关键词追加到末尾（兼容内置与自定义引擎两种写法）。
        let urlStr = searchTemplate.contains("%s")
            ? searchTemplate.replacingOccurrences(of: "%s", with: encoded)
            : searchTemplate + encoded
        // urlStr 理论上恒可构造；非法时兜底 about:blank，再退到文件根 URL，保证非可选返回、杜绝强解包崩溃。
        return URL(string: urlStr) ?? URL(string: "about:blank") ?? URL(fileURLWithPath: "/")
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
