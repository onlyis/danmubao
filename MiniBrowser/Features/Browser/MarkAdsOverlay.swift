import SwiftUI

/// 标记广告模式：网页进入元素选择态，点击高亮要屏蔽的区域，底部确认屏蔽。
struct MarkAdsOverlay: View {
    @EnvironmentObject var vm: BrowserViewModel
    @State private var box: CGRect? = nil
    @State private var showToast = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // 半透明遮罩，点击选取“元素”
                Color.black.opacity(0.12)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        Haptics.soft()
                        withAnimation(.easeOut(duration: 0.18)) {
                            box = CGRect(x: max(16, location.x - 130),
                                         y: max(80, location.y - 40),
                                         width: 260, height: 90)
                        }
                    }

                // 高亮框
                if let box {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Theme.Colors.danger, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .background(Theme.Colors.danger.opacity(0.12))
                        .frame(width: box.width, height: box.height)
                        .position(x: box.midX, y: box.midY)
                        .overlay(alignment: .topLeading) {
                            Text("广告元素")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.Colors.danger, in: Capsule())
                                .position(x: box.minX + 30, y: box.minY - 2)
                        }
                        .allowsHitTesting(false)
                }

                // 顶部说明
                Text(box == nil ? "点击页面中的广告区域" : "已选中 1 个元素，可重新选择")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.7), in: Capsule())
                    .padding(.top, 8)

                // 底部操作栏
                VStack {
                    Spacer()
                    HStack(spacing: Theme.Spacing.m) {
                        actionButton("取消", color: Theme.Colors.secondaryText) { vm.showMarkAds = false }
                        actionButton("重新选择", color: Theme.Colors.accent) { box = nil }
                        actionButton("确认屏蔽", color: Theme.Colors.danger, filled: true) {
                            guard box != nil else { return }
                            withAnimation { showToast = true; box = nil }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                vm.showMarkAds = false
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.m)
                    .background(.bar)
                }

                if showToast {
                    Label("广告已屏蔽", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(.black.opacity(0.8), in: Capsule())
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .transition(.opacity)
    }

    private func actionButton(_ title: String, color: Color, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.light(); action() }) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(filled ? .white : color)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(filled ? color : color.opacity(0.12), in: Capsule())
        }
    }
}
