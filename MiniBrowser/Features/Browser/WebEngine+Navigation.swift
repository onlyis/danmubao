import SwiftUI
import WebKit

/// WebEngine 导航职责：地址加载 / 前进后退 / 内容规则刷新 / 网站设置联动（桌面版·UA·清站数据）/
/// 输入归一化，以及 WKNavigationDelegate、WKUIDelegate（含长按链接下载/后台打开菜单）协议遵从。
extension WebEngine {
    // MARK: - 导航
    func submit(_ text: String, searchTemplate: String) {
        load(Self.normalize(text, searchTemplate: searchTemplate))
    }
    func load(_ url: URL) {
        navigating = true
        loadError = nil                               // 新地址：清掉旧的错误页
        chromeHidden = false; lastScrollY = 0        // 新页面复位顶部栏显隐
        title = ""                                    // 清掉上一页标题，避免加载新页时 header 仍显示旧标题
        displayURL = url.host ?? url.absoluteString    // 立即显示目标地址（而非旧页内容）
        pendingLoadURL = url                          // 记录目标地址（证书失败改 www. 重试时据此重建）
        webView.load(URLRequest(url: url))
    }
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
        loadError = nil      // 开始新导航：清掉旧错误页
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        navigating = false   // 新页面首帧已就绪，撤掉加载遮罩
        loadError = nil      // 已成功提交内容
        wwwRetriedHost = nil // 成功提交，允许后续导航再次触发 www. 重试
        if nightMode { injectNightCSS() }   // 尽早注入反色，避免内容绘制出来先闪白（didFinish 太晚）
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
    /// 额外：裸域名证书对该 host 无效时（很多站点证书只签 *.domain / www，不含裸域，如 hao123.com），
    /// 取消并自动改用 www. 重新加载——这样点「hao123.com」也能正常打开，且不降低安全性（仍走系统校验）。
    func webView(_ webView: WKWebView,
                 didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        latestServerTrust = trust
        let host = challenge.protectionSpace.host
        // 证书对当前 host 是否有效（策略已含 hostname 校验）
        let valid = SecTrustEvaluateWithError(trust, nil)
        if !valid, !host.hasPrefix("www."), host.split(separator: ".").count == 2,
           wwwRetriedHost != host, let target = pendingLoadURL ?? webView.url,
           var comps = URLComponents(url: target, resolvingAgainstBaseURL: false) {
            wwwRetriedHost = host
            comps.host = "www." + host
            if let wwwURL = comps.url {
                completionHandler(.cancelAuthenticationChallenge, nil)
                load(wwwURL)   // 委托方法在主线程回调，直接重载
                return
            }
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
        showLoadError(error)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false; navigating = false
        if retryWithWWWIfNeeded(error) { return }   // 正在改 www. 重试，先不报错
        showLoadError(error)
    }

    /// 展示加载错误页（在内容区自己的区域显示失败，而不是停留在上一页内容）。
    /// 跳过「取消 / 被新导航替换」以及「刚触发 www. 重试的那次失败」。
    private func showLoadError(_ error: Error) {
        let ns = error as NSError
        guard ns.code != NSURLErrorCancelled else { return }
        let failing = ns.userInfo[NSURLErrorFailingURLStringErrorKey] as? String
        if let h = failing.flatMap({ URL(string: $0)?.host }), h == wwwRetriedHost { return }
        loadError = LoadError(url: failing ?? pendingLoadURL?.absoluteString ?? displayURL,
                              message: ns.localizedDescription, code: ns.code)
    }

    /// 重试上次失败的加载。
    func retryFailedLoad() {
        loadError = nil
        if let u = pendingLoadURL { load(u) } else { reload() }
    }

    /// 裸域名证书/连接失败时自动改用 www. 重试一次；返回是否已发起重试。
    /// 很多站点证书只签发给 www.（如 hao123.com 的证书不含裸域），直接打开裸域会证书不匹配而打不开。
    @discardableResult
    private func retryWithWWWIfNeeded(_ error: Error) -> Bool {
        let ns = error as NSError
        // 仅针对证书/安全连接/找不到或连不上主机这类「换 www. 可能可解」的失败。
        let retryCodes: Set<Int> = [
            NSURLErrorSecureConnectionFailed,           // -1200
            NSURLErrorServerCertificateHasBadDate,      // -1201
            NSURLErrorServerCertificateUntrusted,       // -1202
            NSURLErrorServerCertificateHasUnknownRoot,  // -1203
            NSURLErrorServerCertificateNotYetValid,     // -1204
            NSURLErrorCannotFindHost,                   // -1003
            NSURLErrorCannotConnectToHost,              // -1004
        ]
        guard retryCodes.contains(ns.code),
              let failing = ns.userInfo[NSURLErrorFailingURLStringErrorKey] as? String,
              let url = URL(string: failing), let host = url.host,
              wwwRetriedHost != host,
              !host.hasPrefix("www."),
              host.split(separator: ".").count == 2,   // 仅裸的可注册域（如 hao123.com），不动子域
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return false }
        wwwRetriedHost = host
        comps.host = "www." + host
        guard let retryURL = comps.url else { return false }
        load(retryURL)
        return true
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
            guard let url else {
                // 非链接（多为图片）：在系统默认菜单（保存图片等）基础上追加「批量保存图片」。
                let batchSave = UIAction(title: "批量保存图片",
                                         image: UIImage(systemName: "square.and.arrow.down.on.square")) { _ in
                    self?.onBatchSaveImages?()
                }
                return UIMenu(title: "", children: suggested + [batchSave])
            }
            let newTab = UIAction(title: "在新标签页打开",
                                  image: UIImage(systemName: "plus.square.on.square")) { _ in
                self?.onOpenInNewTab?(url)
            }
            let background = UIAction(title: "在后台打开",
                                      image: UIImage(systemName: "rectangle.stack.badge.plus")) { _ in
                self?.onOpenInBackground?(url)
            }
            let download = UIAction(title: "下载链接",
                                    image: UIImage(systemName: "arrow.down.circle")) { _ in
                self?.onRequestDownload?(url)
            }
            return UIMenu(title: url.absoluteString, children: suggested + [newTab, background, download])
        }
        completionHandler(config)
    }
}
