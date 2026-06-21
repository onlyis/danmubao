import SwiftUI

/// 标记广告模式：网页进入元素拾取态，点击页面中的元素即按 CSS 选择器隐藏并按站持久化。
/// 真实流程：本覆盖层仅承载顶部提示与「完成」按钮，元素高亮/命中由 WebEngine 注入的拾取层 JS 完成；
/// VM 轮询取回选择器后立即隐藏并计数。
struct MarkAdsOverlay: View {
    @EnvironmentObject var vm: BrowserViewModel
    /// 本次拾取已屏蔽的元素数（仅用于 UI 计数提示）。
    @State private var hiddenCount = 0

    var body: some View {
        VStack(spacing: 0) {
            // 顶部提示条（不遮挡网页其余区域，让用户能直接点选页面元素）。
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 1) {
                    Text("点选要屏蔽的元素")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(hiddenCount == 0 ? "轻点页面中的广告区域即可隐藏" : "已屏蔽 \(hiddenCount) 个元素，可继续点选")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: Theme.Spacing.s)
                Button(action: finish) {
                    Text("完成")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Colors.danger)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(.white, in: Capsule())
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            .background(Theme.Colors.danger.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.top, Theme.Spacing.s)

            Spacer()
        }
        // 顶部条之外不拦截点击，让用户的点触落到下方 WKWebView 的拾取层。
        .allowsHitTesting(true)
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            hiddenCount = 0
            vm.beginAdElementPick { _ in
                Haptics.soft()
                hiddenCount += 1
            }
        }
        .onDisappear { vm.endAdElementPick() }
    }

    private func finish() {
        Haptics.light()
        if hiddenCount > 0 { vm.showToast("已屏蔽 \(hiddenCount) 个元素", symbol: "checkmark.circle.fill") }
        withAnimation(.easeOut(duration: 0.2)) { vm.showMarkAds = false }
    }
}
