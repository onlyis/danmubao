import SwiftUI

/// 网页浏览页：顶部简化地址栏 + 真实 WKWebView 内容 + 加载进度条。
struct BrowserView: View {
    let engine: WebEngine
    var body: some View {
        BrowserContent(engine: engine)
    }
}

/// 加载失败错误页：占满内容区，显示失败地址与原因 + 重试（类似 404/网络错误页）。
private struct ErrorPageView: View {
    let error: WebEngine.LoadError
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 46)).foregroundStyle(Theme.Colors.tertiaryText)
            Text("无法打开网页").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.Colors.primaryText)
            Text(error.url).font(.system(size: 13)).foregroundStyle(Theme.Colors.secondaryText)
                .lineLimit(2).multilineTextAlignment(.center)
            Text("\(error.message)（错误 \(error.code)）")
                .font(.system(size: 13)).foregroundStyle(Theme.Colors.tertiaryText)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("重试").padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Theme.Colors.accent, in: Capsule()).foregroundStyle(.white)
            }
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background.ignoresSafeArea())
    }
}

private struct BrowserContent: View {
    @EnvironmentObject var vm: BrowserViewModel
    @ObservedObject var engine: WebEngine

    var body: some View {
        VStack(spacing: 0) {
            // 顶部栏随滚动显隐：下滑隐藏、上滑/回到顶部显示（由 engine.chromeHidden 驱动）
            if !engine.chromeHidden {
                VStack(spacing: 0) { addressBar; progressBar }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ZStack(alignment: .bottomTrailing) {
                WebViewContainer(engine: engine)
                    .ignoresSafeArea(.container, edges: .horizontal)   // 横屏时网页内容铺满左右，不留空白
                    .overlay {
                        // 显式加载新地址时遮住旧页面（首帧提交后撤掉）
                        if engine.navigating { Theme.Colors.card.ignoresSafeArea() }
                    }
                    .overlay {
                        // 加载失败：在内容区自己的区域显示错误页，而不是停留在上一页内容
                        if let err = engine.loadError {
                            ErrorPageView(error: err) { engine.retryFailedLoad() }
                        }
                    }
                    // 长按：有选中文本 → 划词浮层；无选中（多为长按链接/图片）→ 让位给原生菜单（含「下载链接」）
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                            engine.fetchSelectedText { text in
                                guard !text.isEmpty else { return }
                                Haptics.soft()
                                vm.selectionText = text
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    vm.showSelectionToolbar = true
                                }
                            }
                        }
                    )
                if vm.hasVideo { pipButton }   // 仅在检测到真实视频时显示悬浮入口
            }
        }
        // 顶部栏等背景也铺到左右屏幕边缘（内容仍在安全区内，避开刘海）
        .background(Theme.Colors.card.ignoresSafeArea(.container, edges: .horizontal))
        // 长按链接的下载 / 后台打开回调统一在 vm.bindActiveEngine 里随引擎激活绑定（切标签也不失效）
        .onChange(of: vm.isDesktopMode) { _, on in engine.setDesktop(on) }
        .onChange(of: vm.isNightMode) { _, on in engine.applyNight(on) }
    }

    /// 无痕态：顶部地址栏用深色作标识（底部工具栏保持常规色）。
    private var inco: Bool { vm.isIncognito }

    private var addressBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            Button {
                Haptics.light(); vm.showControlPanel = true
            } label: {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 17))
                    .foregroundStyle(vm.isAdBlockOn ? Theme.Colors.safe : (inco ? Color.white.opacity(0.7) : Theme.Colors.secondaryText))
            }

            Button { vm.showSearch = true } label: {
                HStack(spacing: 5) {
                    if !engine.displayURL.isEmpty {
                        Image(systemName: "lock.fill").font(.system(size: 10))
                            .foregroundStyle(inco ? Color.white.opacity(0.55) : Theme.Colors.secondaryText)
                    }
                    Text(titleText)
                        .font(.system(size: 15))
                        .foregroundStyle(inco ? Color.white.opacity(0.92) : Theme.Colors.primaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }

            Button { engine.isLoading ? engine.stop() : engine.reload() } label: {
                Image(systemName: engine.isLoading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 16))
                    .foregroundStyle(inco ? Color.white.opacity(0.7) : Theme.Colors.secondaryText)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(height: 44)
        .background(inco ? Color(hex: 0x111114) : Theme.Colors.card)
    }

    /// 地址栏默认展示标题文本；无标题时回退到 host / about:blank。
    private var titleText: String {
        if !engine.title.isEmpty { return engine.title }
        if !engine.displayURL.isEmpty { return engine.displayURL }
        if !vm.currentTitle.isEmpty { return vm.currentTitle }
        return "about:blank"
    }

    @ViewBuilder
    private var progressBar: some View {
        GeometryReader { geo in
            Theme.Colors.accent
                .frame(width: geo.size.width * engine.progress)
                .opacity(engine.isLoading && engine.progress < 1 ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: engine.progress)
        }
        .frame(height: 2)
    }

    private var pipButton: some View {
        Button { vm.requestVideoPiP() } label: {   // 悬浮播放：视频整体画中画浮出（长按可改开控制面板）
            Image(systemName: "pip.enter")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(Circle().fill(Theme.Colors.accent))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        }
        // 长按：改开悬浮控制面板（含倍速/进度/±15s 等控制）
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
            Haptics.soft(); vm.openVideoFloat()
        })
        .padding(Theme.Spacing.l)
        .padding(.bottom, 4)
    }
}
