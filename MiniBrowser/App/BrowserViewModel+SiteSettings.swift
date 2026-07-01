import Foundation

/// BrowserViewModel 网站设置（按当前域名）职责扩展：
/// User-Agent 切换、按站清除 Cookie/缓存、重置广告规则与站点权限、拦截跳转开关、查看站点证书。
extension BrowserViewModel {

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
}
