import SwiftUI

/// BrowserViewModel 功能动作职责扩展：
/// 菜单/控制面板按标题的统一功能分发（performMenuAction），以及各功能的真实实现——
/// 网页导出/打印/源码、广告/无图开关、分享、视频增强、阅读/漫画/翻译、网页保存、
/// 自动刷新/全屏、PDF/文本/压缩、标记广告、媒体嗅探、稍后读、书签、看图。
extension BrowserViewModel {

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

    // MARK: - 广告拦截 / 无图模式
    /// 切换广告拦截：驱动所有已安装的广告类插件启用/停用；isAdBlockOn 经由管道回流刷新。
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
    func shareCurrentPage() {
        let s = currentURL
        guard !s.isEmpty else { showToast("无可分享的页面", symbol: "exclamationmark.circle"); return }
        guard let u = s.asWebURL() else { showToast("无可分享的页面", symbol: "exclamationmark.circle"); return }
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

    // MARK: - 自动刷新（循环档位: 0=关 / 15 / 30 / 60 秒）
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
    /// 切换全屏模式, 并给出提示。
    func toggleFullScreen() {
        withAnimation(.easeInOut(duration: 0.2)) { isFullScreen.toggle() }
        showToast(isFullScreen ? "已进入全屏" : "已退出全屏",
                  symbol: isFullScreen ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
    }

    // MARK: - workflow 批量功能（视频增强/漫画/翻译/PDF/文本/压缩）
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
    /// 用 PDF 阅读器打开指定目录内 PDF（默认下载目录，支持子文件夹）。
    func openPDF(fileName: String, in dir: URL = DownloadManager.downloadsDirectory) {
        let url = dir.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { showToast("文件不存在", symbol: "exclamationmark.circle"); return }
        pdfPreviewURL = PDFPreviewItem(url: url)
    }
    /// 以纯文本打开指定目录内文件。
    func openTextFile(named name: String, in dir: URL = DownloadManager.downloadsDirectory) { textFileURL = dir.appendingPathComponent(name) }
    /// 压缩指定目录里的图片。
    @discardableResult
    func compressImage(name: String, in dir: URL = DownloadManager.downloadsDirectory) -> Bool {
        do {
            let result = try ImageCompressor.compress(fileName: name, in: dir)
            let before = ByteCountFormatter.string(fromByteCount: result.originalBytes, countStyle: .file)
            let after = ByteCountFormatter.string(fromByteCount: result.compressedBytes, countStyle: .file)
            showToast("已压缩：\(before) → \(after)（省 \(Int((result.savedRatio*100).rounded()))%）", symbol: "photo.badge.arrow.down")
            return true
        } catch { showToast("压缩失败：\(error.localizedDescription)", symbol: "exclamationmark.triangle.fill"); return false }
    }

    // MARK: - 标记广告（点选元素 → 隐藏并按站持久化）
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

    // MARK: - 媒体嗅探（页面内 <video>/<audio> 地址收集 + 下载/复制/分享）
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

    // MARK: - 看图模式
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
}
