import SwiftUI

/// 视频悬浮播放器：浮在网页之上、可拖拽、带控制条。带边缘吸附效果。
struct FloatingVideoPlayer: View {
    @EnvironmentObject var vm: BrowserViewModel
    @State private var offset = CGSize(width: -16, height: 120)
    @State private var dragStart = CGSize.zero
    @State private var speed = 1.0

    private let size = CGSize(width: 260, height: 150)

    var body: some View {
        VStack(spacing: 0) {
            // 画面
            ZStack {
                LinearGradient(colors: [Color(hex: 0x3A5A8A), Color(hex: 0x6B5B95)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // 顶部行：分享 + 倍速
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "square.and.arrow.up").foregroundStyle(.white)
                        Text(String(format: "%.1f", speed))
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                            .onTapGesture { speed = speed >= 2 ? 0.5 : speed + 0.5 }
                    }
                    .padding(8)
                    Spacer()
                    // 底部控制
                    HStack(spacing: 14) {
                        Text("13:29").font(.system(size: 11)).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "headphones").foregroundStyle(.white)
                        Image(systemName: "repeat.1").foregroundStyle(.white)
                        Image(systemName: "arrow.down.left.and.arrow.up.right").foregroundStyle(.white)
                    }
                    .font(.system(size: 14))
                    .padding(8)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                Image(systemName: "play.fill").font(.system(size: 30)).foregroundStyle(.white.opacity(0.85))
            }
            .overlay(alignment: .topLeading) {
                Button { vm.showVideoFloat = false } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .padding(6).background(Circle().fill(.black.opacity(0.4)))
                }
                .padding(6)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        .offset(offset)
        .gesture(
            DragGesture()
                .onChanged { v in
                    offset = CGSize(width: dragStart.width + v.translation.width,
                                    height: dragStart.height + v.translation.height)
                }
                .onEnded { _ in
                    dragStart = offset
                    snapToEdge()
                }
        )
        .padding(.top, 8)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: offset)
    }

    /// 边缘吸附
    private func snapToEdge() {
        let screenW = UIScreen.main.bounds.width
        let leftEdge = -(screenW - size.width) / 2 + 8
        let rightEdge = (screenW - size.width) / 2 - 8
        // offset 相对 topTrailing，向左为负
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            offset.width = offset.width < -(screenW - size.width) / 2 ? leftEdge : min(offset.width, rightEdge)
        }
        dragStart = offset
    }
}
