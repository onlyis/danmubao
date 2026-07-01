import SwiftUI

/// BrowserViewModel 标签页职责扩展：
/// 标签新建/关闭/切换/移动/无痕切换、引擎激活绑定、导航动作（open/back/forward/home）、标签持久化。
extension BrowserViewModel {

    // MARK: - 标签持久化（合并写，避免连续增删反复整表编码）
    /// 标签结构/地址变化后调用：延迟合并为一次落盘（普通 + 无痕都持久化）。
    func scheduleTabPersist() {
        tabPersistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistTabsNow() }
        tabPersistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
    /// 立即落盘（供 App 进入后台时调用，捕获最新标题/地址）。
    func persistTabsNow() {
        // 快照在主线程取（Tab 是 @MainActor），编码+写盘交给后台，避免海量标签整表编码卡主线程。
        let state = TabsState(tabs: tabs.map(\.snapshot), currentID: savedNormalID,
                              incognitoTabs: incognitoTabs.map(\.snapshot), incognitoCurrentID: savedIncognitoID)
        DiskStore.saveAsync(state, to: PersistenceKey.tabs)
    }

    // MARK: - 导航动作
    func open(url: String, title: String? = nil) {
        showSearch = false
        if currentTab == nil { newTab() }   // 没有可用标签（如刚切到无痕）
        if let t = currentTab {
            t.load(url, searchTemplate: searchTemplate)   // 本页面打开；加载遮罩避免看到旧页面
            enginePool.touch(t, current: t)
            bindActiveEngine(t)   // 跟随全局夜间/桌面开关
        }
        isBrowsing = true
        if !isIncognito { library.recordHistory(title: title ?? url, url: url) }
        scheduleTabPersist()
    }

    func goHome() {
        isBrowsing = false
        hasVideo = false   // 主页无网页视频，收起悬浮入口
    }

    /// 激活某标签引擎时统一绑定：①同步全局页面开关（夜间/桌面）②加载完成回填历史标题
    /// ③长按链接的下载 / 后台打开回调。标签激活/加载后调用——切标签、新标签都重新绑定，
    /// 避免状态与回调只挂在最初那个引擎上（切标签后失效）。
    private func bindActiveEngine(_ tab: Tab?) {
        guard let tab, !tab.isHome else { return }
        // 主动取 engine：被 LRU 回收的标签在此惰性重建并恢复会话，
        // 保证「夜间/桌面同步 + 各回调」一定绑到将要显示的这个引擎上（不会因尚未创建而漏绑）。
        let engine = tab.engine
        engine.syncPageState(night: isNightMode, desktop: isDesktopMode)
        engine.blockRedirects = blockRedirects   // 同步「拦截跳转」开关到该引擎
        engine.onBlockedRedirect = { [weak self] url in
            self?.showToast("已拦截跳转：\(url.host ?? url.absoluteString)", symbol: "hand.raised.fill")
        }
        // 应用本站已保存的广告隐藏规则（按 host 归一化匹配），随引擎激活生效。
        engine.applyAdHide(AdHideStore.shared.selectors(for: engine.webView.url?.host))
        refreshVideoPresence(for: tab)   // 切到/加载该标签时检测是否有视频
        engine.onDidFinish = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.refreshVideoPresence(for: tab)   // 加载完成后重检测视频（驱动悬浮入口显隐）
            if self.defaultVideoRate != 1.0 { tab.engine.videoSetRate(self.defaultVideoRate) }   // 应用默认倍速（无视频时为空操作）
            guard !tab.isIncognito, let pending = tab.pendingHistoryURL else { return }
            let title = tab.engine.title
            guard !title.isEmpty else { return }
            tab.pendingHistoryURL = nil
            self.library.updateHistoryTitle(url: pending, title: title)
        }
        engine.onRequestDownload = { [weak self] url in
            self?.downloadManager?.start(urlString: url.absoluteString)
            self?.showToast("开始下载…", symbol: "arrow.down.circle")
        }
        engine.onOpenInBackground = { [weak self] url in self?.openInBackground(url: url.absoluteString) }
    }

    /// 在后台新标签打开链接（不切换当前标签）
    func openInBackground(url: String) {
        let u = url.trimmingCharacters(in: .whitespaces)
        guard !u.isEmpty else { return }
        let tab = Tab(isHome: false, isIncognito: isIncognito)
        tabIndex[tab.id] = tab
        if isIncognito { incognitoTabs.append(tab) } else { tabs.append(tab) }   // 末尾
        tab.load(u, searchTemplate: searchTemplate)
        bindActiveEngine(tab)   // 后台标签也跟随全局夜间/桌面开关
        if !isIncognito { library.recordHistory(title: u, url: u) }
        bgOpenTrigger += 1   // 小动画替代提示
        scheduleTabPersist()
    }

    /// 截取当前标签缩略图（打开标签管理前调用）
    func captureCurrentThumbnail() { currentTab?.captureThumbnail() }

    /// 手势滑动切换到相邻标签（环绕），离开前先截图当前标签。
    func switchTab(by offset: Int) {
        let tabs = activeTabs
        guard tabs.count > 1, let cur = currentTab,
              let idx = tabs.firstIndex(where: { $0.id == cur.id }) else { return }
        cur.captureThumbnail()
        let next = tabs[(idx + offset + tabs.count) % tabs.count]
        select(next)
        if next.isHome { showToast("新标签页", symbol: "house") }
        else { showToast(next.displayTitle, symbol: "square.on.square") }
    }

    /// 拖动重排：把 from 移到 to 之前（当前模式的标签数组内）
    func moveTab(_ from: Tab, before to: Tab) {
        guard from.id != to.id, from.isIncognito == to.isIncognito else { return }
        if isIncognito { reorder(&incognitoTabs, from, to) } else { reorder(&tabs, from, to) }
    }
    private func reorder(_ arr: inout [Tab], _ from: Tab, _ to: Tab) {
        guard let f = arr.firstIndex(where: { $0.id == from.id }),
              let t = arr.firstIndex(where: { $0.id == to.id }) else { return }
        let item = arr.remove(at: f)
        let dest = t > f ? t - 1 : t
        arr.insert(item, at: dest)
        scheduleTabPersist()
    }

    /// 选择某个标签
    func select(_ tab: Tab) {
        currentTabID = tab.id
        isIncognito = tab.isIncognito
        if tab.isHome {
            isBrowsing = false
        } else {
            tab.activateIfNeeded(searchTemplate: searchTemplate)
            enginePool.touch(tab, current: tab)
            bindActiveEngine(tab)   // 切到该标签时对齐全局夜间/桌面开关
            isBrowsing = true
        }
        showTabs = false
        scheduleTabPersist()
    }

    /// 后退：优先网页历史，无历史则退回主页
    func back() {
        if let engine, engine.canGoBack { engine.goBack() }
        else { goHome() }
    }

    func forward() {
        if let engine, engine.canGoForward { engine.goForward() }
    }

    func newTab() {
        let tab = Tab(isHome: true, isIncognito: isIncognito)
        tabIndex[tab.id] = tab
        if isIncognito { incognitoTabs.append(tab) } else { tabs.append(tab) }   // 新标签在末尾
        currentTabID = tab.id
        // 设置「新标签默认打开主页」时直接加载主页地址，否则空白新标签页。
        let home = homepageURL.trimmingCharacters(in: .whitespaces)
        if newTabOpensHomepage, !home.isEmpty { open(url: home) } else { goHome() }
        pagePopTrigger += 1   // 触发新页面左下角弹出动画
        scheduleTabPersist()
    }

    func close(_ tab: Tab) {
        let wasCurrent = tab.id == currentTabID
        enginePool.remove(tab)
        tabIndex[tab.id] = nil
        withAnimation {
            if isIncognito { incognitoTabs.removeAll { $0.id == tab.id } }
            else { tabs.removeAll { $0.id == tab.id } }
        }
        if wasCurrent {
            currentTabID = activeTabs.first?.id
            isBrowsing = false
        }
        scheduleTabPersist()
    }

    func closeAllActive() {
        let closing = activeTabs
        for t in closing { enginePool.remove(t); tabIndex[t.id] = nil }
        withAnimation {
            if isIncognito { incognitoTabs.removeAll() } else { tabs.removeAll() }
        }
        currentTabID = nil
        isBrowsing = false
        scheduleTabPersist()
    }

    func toggleIncognito() {
        // 切换前先把当前模式的当前标签存进对应槽，切换后恢复目标模式上次的当前标签（互不干扰）。
        if isIncognito { incognitoCurrentID = currentTabID } else { normalCurrentID = currentTabID }
        withAnimation { isIncognito.toggle() }
        let restored = isIncognito ? incognitoCurrentID : normalCurrentID
        currentTabID = restored ?? activeTabs.first?.id
        if let t = currentTab, !t.isHome {
            t.activateIfNeeded(searchTemplate: searchTemplate)
            enginePool.touch(t, current: t)
            bindActiveEngine(t)
            isBrowsing = true
        } else {
            isBrowsing = false
            hasVideo = false
        }
        scheduleTabPersist()
    }
}
