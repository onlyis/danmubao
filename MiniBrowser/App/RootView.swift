import SwiftUI

/// 根视图：协调 主页/网页 主体、底部工具栏、各类弹出层与全屏页面。
struct RootView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @EnvironmentObject var toasts: ToastStore
    @Environment(\.colorScheme) private var systemScheme
    @State private var pagePop: CGFloat = 1

    /// 当前是否处于深色（用于 OLED 纯黑判断）
    private var isDark: Bool {
        if vm.isIncognito || vm.isNightMode { return true }
        switch vm.appearanceMode {
        case .light: return false
        case .dark: return true
        case .system: return systemScheme == .dark
        }
    }

    @ViewBuilder
    private var rootBackground: some View {
        if !vm.isBrowsing && vm.wallpaper != .none && !vm.isIncognito {
            WallpaperBackground(wallpaper: vm.wallpaper)
        } else if vm.isIncognito || (isDark && vm.oledBlack) {
            Color.black
        } else {
            Theme.Colors.background
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            rootBackground.ignoresSafeArea()

            // 主体内容
            Group {
                if vm.isBrowsing, let engine = vm.currentTab?.engine {
                    BrowserView(engine: engine)
                } else {
                    HomeView()
                }
            }
            .padding(.bottom, Theme.Size.toolbarHeight)
            .scaleEffect(pagePop, anchor: .bottomLeading)   // 新建标签：从左下角弹出（快）
            .onChange(of: vm.pagePopTrigger) { _, _ in
                pagePop = 0.1
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { pagePop = 1 }
            }

            // 底部固定工具栏（主页态不创建引擎）
            BottomToolbar(engine: vm.isBrowsing ? vm.currentTab?.engine : nil)

            // 悬浮手势按钮（覆盖全屏以承载笔画轨迹）
            if vm.gesture.enabled { GestureButton() }
        }
        .preferredColorScheme(vm.resolvedScheme)
        // 底部主菜单
        .sheet(isPresented: $vm.showMenu) {
            MainMenuSheet()
                .presentationDetents([.height(560), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        // 标签页管理：覆盖层瞬时显示/消失（不显示标签淡出动画，只看新页面弹出）
        .overlay {
            if vm.showTabs { TabsView().zIndex(20) }
        }
        // 网站设置面板
        .sheet(isPresented: $vm.showWebsiteSettings) {
            WebsiteSettingsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        // 搜索输入态：统一的内联搜索（主页/浏览态共用），覆盖层淡入
        .overlay {
            if vm.showSearch {
                InlineSearchView(
                    onSubmit: { q in vm.recordSearch(q); vm.open(url: q, title: q); vm.showSearch = false },
                    onCancel: { vm.showSearch = false }
                )
                .transition(.opacity)
                .zIndex(25)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: vm.showSearch)
        // 下载确认
        .sheet(isPresented: $vm.showDownloadConfirm) {
            DownloadConfirmSheet()
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        // 全屏路由页面
        .fullScreenCover(item: $vm.route) { route in
            NavigationStack { routeView(route) }
        }
        // 视频悬浮窗
        .overlay(alignment: .topTrailing) {
            if vm.showVideoFloat { FloatingVideoPlayer() }
        }
        // 标记广告模式
        .overlay {
            if vm.showMarkAds && vm.isBrowsing { MarkAdsOverlay() }
        }
        // 划词翻译 / BigBang 浮层
        .overlay(alignment: .top) {
            if vm.showSelectionToolbar && vm.isBrowsing { SelectionToolbar() }
        }
        // 网页源码查看
        .sheet(item: $vm.sourcePreview) { preview in
            SourceCodeView(code: preview.code)
        }
        // 全局轻提示
        .overlay {
            if let toast = toasts.toast { ToastView(message: toast) }
        }
    }

    @ViewBuilder
    private func routeView(_ route: BrowserViewModel.Route) -> some View {
        switch route {
        case .bookmarks:    BookmarksView()
        case .history:      HistoryView()
        case .downloads:    DownloadsView()
        case .files:        FilesView()
        case .settings:     SettingsView()
        case .reading:      ReadingModeView()
        case .imageViewer:  ImageGridView()
        case .comic:        ComicReaderView()
        case .toolbox:      ToolboxView()
        case .qrScanner:    QRScannerView()
        case .reader:       EbookLibraryView()
        case .translate:    TranslateView()
        case .jsExtensions: JSExtensionsView()
        case .devtools:     DevToolsView()
        case .cookies:      CookieManagerView()
        case .gestures:     GestureSettingsView()
        case .plugins:      PluginMarketView()
        case .searchEngine: SearchEngineView()
        }
    }
}
