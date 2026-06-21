import SwiftUI

/// 视频悬浮控制器：浮在网页之上、可拖拽吸附。
/// 不再是假画面——直接控制页面里真实的 `<video>`（播放/暂停、±15s、倍速、画中画），并显示真实进度。
struct FloatingVideoPlayer: View {
    @EnvironmentObject var vm: BrowserViewModel
    @State private var offset = CGSize(width: -16, height: 120)
    @State private var dragStart = CGSize.zero
    @State private var state: WebEngine.VideoState?

    private let size = CGSize(width: 260, height: 96)
    /// 每 0.5s 拉取一次真实播放状态
    private let ticker = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var engine: WebEngine? { vm.engine }
    private var paused: Bool { state?.paused ?? true }
    private var rate: Double { state?.rate ?? 1 }

    var body: some View {
        VStack(spacing: 8) {
            // 顶部：标题 + 倍速 + 画中画 + 关闭
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill").foregroundStyle(.white.opacity(0.9))
                Text(timeText).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Button { cycleRate() } label: {
                    Text(String(format: "%.2g×", rate))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                }
                Button { engine?.videoRequestPiP() } label: {
                    Image(systemName: "pip.enter").foregroundStyle(.white)
                }
                Button { vm.showVideoFloat = false } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                }
            }
            .font(.system(size: 15))

            // 进度条
            ProgressView(value: progress).tint(Theme.Colors.accent)

            // 主控制：−15s / 播放暂停 / +15s
            HStack(spacing: 28) {
                Button { engine?.videoSeek(by: -15); refresh() } label: {
                    Image(systemName: "gobackward.15").font(.system(size: 20)).foregroundStyle(.white)
                }
                Button { engine?.videoTogglePlay(); refresh() } label: {
                    Image(systemName: paused ? "play.fill" : "pause.fill").font(.system(size: 24)).foregroundStyle(.white)
                }
                Button { engine?.videoSeek(by: 15); refresh() } label: {
                    Image(systemName: "goforward.15").font(.system(size: 20)).foregroundStyle(.white)
                }
            }
        }
        .padding(12)
        .frame(width: size.width)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        .offset(offset)
        .gesture(
            DragGesture()
                .onChanged { v in
                    offset = CGSize(width: dragStart.width + v.translation.width,
                                    height: dragStart.height + v.translation.height)
                }
                .onEnded { _ in dragStart = offset; snapToEdge() }
        )
        .padding(.top, 8)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: offset)
        .onReceive(ticker) { _ in refresh() }
        .onAppear { refresh() }
    }

    private var progress: Double {
        guard let s = state, s.duration > 0 else { return 0 }
        return min(max(s.current / s.duration, 0), 1)
    }
    private var timeText: String {
        guard let s = state else { return "—" }
        return "\(fmt(s.current)) / \(s.duration > 0 ? fmt(s.duration) : "—")"
    }
    private func fmt(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let s = Int(t); return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func refresh() {
        engine?.fetchVideoState { st in
            self.state = st
            // 视频已从页面消失（如关闭/跳转）则收起悬浮窗
            if st == nil { vm.showVideoFloat = false }
        }
    }
    private func cycleRate() {
        let next = rate >= 2 ? 0.5 : (rate + 0.5)
        engine?.videoSetRate(next); refresh()
    }

    private func snapToEdge() {
        let screenW = UIScreen.main.bounds.width
        let leftEdge = -(screenW - size.width) / 2 + 8
        let rightEdge = (screenW - size.width) / 2 - 8
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            offset.width = offset.width < -(screenW - size.width) / 2 ? leftEdge : min(offset.width, rightEdge)
        }
        dragStart = offset
    }
}
