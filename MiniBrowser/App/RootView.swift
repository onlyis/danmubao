import SwiftUI

/// 根视图：协调 主页/网页 主体、底部工具栏、各类弹出层与全屏页面。
struct RootView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @EnvironmentObject var toasts: ToastStore
    @Environment(\.colorScheme) private var systemScheme

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

            // 底部固定工具栏（主页态不创建引擎）
            BottomToolbar(engine: vm.isBrowsing ? vm.currentTab?.engine : nil)

            // 悬浮手势按钮（覆盖全屏以承载笔画轨迹）
            if vm.gesture.enabled { GestureButton() }
        }
        .preferredColorScheme(vm.resolvedScheme)
        // 底部主菜单
        .sheet(isPresented: $vm.showMenu) {
            MainMenuSheet()
                .presentationDetents([.height(440), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        // 标签页管理
        .fullScreenCover(isPresented: $vm.showTabs) { TabsView() }
        // 网站设置面板
        .sheet(isPresented: $vm.showWebsiteSettings) {
            WebsiteSettingsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        // 搜索输入态
        .fullScreenCover(isPresented: $vm.showSearch) { SearchOverlay() }
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
        case .adblock:      AdBlockView()
        case .jsExtensions: JSExtensionsView()
        case .devtools:     DevToolsView()
        case .cookies:      CookieManagerView()
        case .gestures:     GestureSettingsView()
        }
    }
}
