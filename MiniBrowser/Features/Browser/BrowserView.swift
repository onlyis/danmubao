import SwiftUI

/// 网页浏览页：顶部简化地址栏 + 真实 WKWebView 内容 + 加载进度条。
struct BrowserView: View {
    let engine: WebEngine
    var body: some View {
        BrowserContent(engine: engine)
    }
}

private struct BrowserContent: View {
    @EnvironmentObject var vm: BrowserViewModel
    @ObservedObject var engine: WebEngine

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            progressBar
            ZStack(alignment: .bottomTrailing) {
                WebViewContainer(engine: engine)
                    .overlay {
                        // 显式加载新地址时遮住旧页面（首帧提交后撤掉）
                        if engine.navigating { Theme.Colors.card.ignoresSafeArea() }
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
        .background(Theme.Colors.card)
        // 长按链接的下载 / 后台打开回调统一在 vm.bindActiveEngine 里随引擎激活绑定（切标签也不失效）
        .onChange(of: vm.isDesktopMode) { _, on in engine.setDesktop(on) }
        .onChange(of: vm.isNightMode) { _, on in engine.applyNight(on) }
    }

    private var addressBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            Button {
                Haptics.light(); vm.showControlPanel = true
            } label: {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 17))
                    .foregroundStyle(vm.isAdBlockOn ? Theme.Colors.safe : Theme.Colors.secondaryText)
            }

            Button { vm.showSearch = true } label: {
                HStack(spacing: 5) {
                    if !engine.displayURL.isEmpty {
                        Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.Colors.secondaryText)
                    }
                    Text(titleText)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Colors.primaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }

            Button { engine.isLoading ? engine.stop() : engine.reload() } label: {
                Image(systemName: engine.isLoading ? "xmark" : "arrow.clockwise")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(height: 44)
        .background(Theme.Colors.card)
    }

    private var titleText: String {
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
        Button { vm.openVideoFloat() } label: {
            Image(systemName: "pip.enter")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(12)
                .background(Circle().fill(Theme.Colors.accent))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        }
        .padding(Theme.Spacing.l)
        .padding(.bottom, 4)
    }
}
