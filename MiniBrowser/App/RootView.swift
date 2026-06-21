import SwiftUI

/// 根视图：协调 主页/网页 主体、底部工具栏、各类弹出层与全屏页面。
struct RootView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @EnvironmentObject var toasts: ToastStore
    @Environment(\.colorScheme) private var systemScheme
    @State private var pagePop: CGFloat = 1

    /// 当前是否处于深色（用于 OLED 纯黑判断）。只看外观模式——网页夜间模式不影响 App 外观。
    private var isDark: Bool {
        switch vm.appearanceMode {
        case .light: return false
        case .dark: return true
        case .system: return systemScheme == .dark
        }
    }

    @ViewBuilder
    private var rootBackground: some View {
        if !vm.isBrowsing && vm.wallpaper != .none {
            WallpaperBackground(wallpaper: vm.wallpaper)
        } else if isDark && vm.oledBlack {
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
                if vm.isBrowsing, let tab = vm.currentTab {
                    // .id(tab.id)：切标签/切无痕时，让 SwiftUI 重新挂载对应引擎的 WKWebView，
                    // 否则 UIViewRepresentable 会复用上一个标签的 webView，导致内容不切换（停在旧页）。
                    BrowserView(engine: tab.engine).id(tab.id)
                } else {
                    HomeView()
                }
            }
            .padding(.bottom, Theme.Size.toolbarHeight)
            .scaleEffect(pagePop, anchor: .bottomLeading)   // 新建标签：从左下角弹出（快）
            .onChange(of: vm.pagePopTrigger) { _, _ in
                pagePop = 0.1
                withAnimation(.spring(response: 0.18, dampingFraction: 0.78)) { pagePop = 1 }
            }

            // 底部固定工具栏（全屏模式下隐藏）
            if !vm.isFullScreen {
                BottomToolbar(engine: vm.isBrowsing ? vm.currentTab?.engine : nil)
            }
        }
        .preferredColorScheme(vm.resolvedScheme)
        // 底部主菜单
        .sheet(isPresented: $vm.showMenu) {
            MainMenuSheet()
                .presentationDetents([.height(560), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.Radius.sheet)
                .presentationBackground(vm.isIncognito ? Color(hex: 0x111114) : Theme.Colors.card)
        }
        // 标签页管理：覆盖层瞬时显示/消失（不显示标签淡出动画，只看新页面弹出）
        .overlay {
            if vm.showTabs { TabsView().zIndex(20) }
        }
        // 盾牌控制面板（网页快捷操作，可自定义）
        .sheet(isPresented: $vm.showControlPanel) { ControlPanelSheet() }
        .sheet(isPresented: $vm.showQRGenerate) {
            QRGenerateSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        // 网站设置面板（详细）
        .sheet(isPresented: $vm.showWebsiteSettings) {
            WebsiteSettingsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.Radius.sheet)
        }
        // 系统分享面板
        .sheet(item: $vm.shareItem) { item in
            ActivityView(items: [item.url])
                .presentationDetents([.medium, .large])
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
        // 悬浮手势按钮：全局最顶层，覆盖搜索/标签等所有页面（仅按钮区域拦截触摸）
        .overlay { if vm.gesture.enabled { GestureButton() } }
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
        // 全屏退出浮动按钮（仅全屏模式显示）
        .overlay(alignment: .bottomTrailing) {
            if vm.isFullScreen {
                Button { vm.toggleFullScreen() } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .padding(.trailing, 16).padding(.bottom, 28)
                .transition(.opacity).zIndex(30)
            }
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
