import SwiftUI

/// BrowserViewModel 手势与工具栏自定义职责扩展：
/// 手势放置方式切换、底部工具栏按钮增删/重排、手势方向匹配与命中功能执行。
extension BrowserViewModel {

    // MARK: - 手势放置方式
    /// 切换手势放置方式：工具栏模式则把 `.gesture` 并入工具栏，悬浮模式则移出。
    func setGesturePlacement(_ p: GesturePlacement) {
        gesture.placement = p
        if p == .toolbar {
            if !toolbarItems.contains(.gesture), toolbarItems.count < 8 { toolbarItems.append(.gesture) }
        } else {
            toolbarItems.removeAll { $0 == .gesture }
        }
    }

    // MARK: - 工具栏自定义（1…8 个，任意功能）
    func addToolbarItem(_ k: ToolbarItemKind) {
        guard toolbarItems.count < 8, !toolbarItems.contains(k) else { return }
        toolbarItems.append(k)
        if k == .gesture { gesture.placement = .toolbar }
    }
    func removeToolbarItem(_ k: ToolbarItemKind) {
        guard toolbarItems.count > 1 else { return }
        toolbarItems.removeAll { $0 == k }
        if k == .gesture { gesture.placement = .floating }
    }
    func moveToolbarItems(from: IndexSet, to: Int) {
        toolbarItems.move(fromOffsets: from, toOffset: to)
    }

    // MARK: - 手势
    /// 匹配方向序列到启用规则
    func matchGesture(_ directions: [GestureDirection]) -> GestureAction? {
        guard !directions.isEmpty else { return nil }
        return gesture.rules.first { $0.enabled && $0.directions == directions }?.action
    }

    /// 执行手势命中的功能
    func perform(_ action: GestureAction) {
        switch action {
        case .back: back()
        case .forward: forward()
        case .reload: engine?.reload()
        case .newTab: newTab()
        case .closeTab: if let t = currentTab { close(t) }
        case .home: goHome()
        case .tabs: showTabs = true
        case .menu: showMenu = true
        case .bookmarks: route = .bookmarks
        case .history: route = .history
        case .downloads: route = .downloads
        case .files: route = .files
        case .settings: route = .settings
        case .toggleNight: withAnimation { isNightMode.toggle() }
        case .toggleIncognito: toggleIncognito()
        case .translate: route = .translate
        case .reading: route = .reading
        case .imageMode: route = .imageViewer
        case .qrScan: route = .qrScanner
        case .addBookmark: addBookmark(title: currentTitle, url: currentURL); return
        case .copyURL:
            UIPasteboard.general.string = currentURL
            showToast("已复制网址", symbol: "doc.on.doc"); return
        case .scrollTop:
            engine?.webView.evaluateJavaScript("window.scrollTo({top:0,behavior:'smooth'})")
        case .scrollBottom:
            engine?.webView.evaluateJavaScript("window.scrollTo({top:document.body.scrollHeight,behavior:'smooth'})")
        }
        if gesture.haptics { Haptics.soft() }
        showToast(action.title, symbol: action.symbol)
    }
}
