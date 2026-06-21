import SwiftUI

/// 悬浮手势按钮：按住从按钮拖出笔画 → 实时识别方向序列 → 松手命中规则执行。
/// 长按按钮可拾起并移动位置；轻点打开手势配置。
struct GestureButton: View {
    @EnvironmentObject var vm: BrowserViewModel

    private enum Phase { case idle, deciding, gesturing, moving }
    @State private var phase: Phase = .idle
    @State private var points: [CGPoint] = []
    @State private var recognized: [GestureDirection] = []
    @State private var matched: GestureAction?
    @State private var livePos: CGPoint?
    @State private var liftWork: DispatchWorkItem?

    private let coordSpace = "gestureRoot"
    private var radius: CGFloat { 27 * vm.gesture.buttonSize }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 轨迹与提示（不拦截触摸）
                if phase == .gesturing {
                    trail
                    hud(in: geo.size)
                }
                button
                    .position(center(in: geo.size))
                    .gesture(drag(in: geo.size))
            }
            .coordinateSpace(name: coordSpace)
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    // MARK: - 按钮
    private var button: some View {
        ZStack {
            Circle()
                .fill(phase == .moving ? Theme.Colors.accent : Theme.Colors.accent.opacity(0.92))
                .frame(width: radius * 2, height: radius * 2)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            Image(systemName: "hand.draw.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
        }
        .scaleEffect(phase == .gesturing ? 1.12 : (phase == .moving ? 1.18 : 1))
        .opacity(phase == .gesturing ? 0.85 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: phase)
    }

    // MARK: - 轨迹
    private var trail: some View {
        Canvas { ctx, _ in
            guard points.count > 1 else { return }
            var path = Path()
            path.move(to: points[0])
            for p in points.dropFirst() { path.addLine(to: p) }
            ctx.stroke(path, with: .color(Theme.Colors.accent.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            if let last = points.last {
                ctx.fill(Path(ellipseIn: CGRect(x: last.x - 6, y: last.y - 6, width: 12, height: 12)),
                         with: .color(Theme.Colors.accent))
            }
        }
        .allowsHitTesting(false)
    }

    // 顶部提示：识别到的方向 + 命中功能
    private func hud(in size: CGSize) -> some View {
        VStack(spacing: 6) {
            Text(recognized.isEmpty ? "滑动绘制手势…" : recognized.glyphs)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
            if let matched {
                Label(matched.title, systemImage: matched.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.Colors.accent, in: Capsule())
            } else if !recognized.isEmpty {
                Text("未匹配").font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
        .position(x: size.width / 2, y: max(120, size.height * 0.22))
        .allowsHitTesting(false)
    }

    // MARK: - 位置
    private func center(in size: CGSize) -> CGPoint {
        if phase == .moving, let livePos { return clamp(livePos, in: size) }
        return clamp(CGPoint(x: vm.gesture.posX * size.width, y: vm.gesture.posY * size.height), in: size)
    }
    private func clamp(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let m = radius + 6
        return CGPoint(x: min(max(p.x, m), size.width - m),
                       y: min(max(p.y, m), size.height - m))
    }

    // MARK: - 手势
    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordSpace))
            .onChanged { v in
                switch phase {
                case .idle:
                    phase = .deciding
                    points = [v.location]
                    let work = DispatchWorkItem {
                        if phase == .deciding { phase = .moving; livePos = v.location; Haptics.soft() }
                    }
                    liftWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
                case .deciding:
                    if hypot(v.translation.width, v.translation.height) > 12 {
                        liftWork?.cancel()
                        phase = .gesturing
                        points = [v.startLocation, v.location]
                    }
                case .gesturing:
                    // 抽稀：忽略过近的点，限制 points 增长与重复识别开销
                    if let last = points.last,
                       hypot(v.location.x - last.x, v.location.y - last.y) < 4 { break }
                    points.append(v.location)
                    recognized = GestureRecognizer.recognize(points, segment: vm.gesture.recognizeSegment, detectCircle: vm.gesture.enableCircle)
                    matched = vm.matchGesture(recognized)
                case .moving:
                    livePos = v.location
                }
            }
            .onEnded { v in
                liftWork?.cancel()
                switch phase {
                case .gesturing:
                    let dirs = GestureRecognizer.recognize(points, segment: vm.gesture.recognizeSegment, detectCircle: vm.gesture.enableCircle)
                    if let action = vm.matchGesture(dirs) {
                        vm.perform(action)
                    } else if !dirs.isEmpty {
                        vm.showToast("未匹配手势 \(dirs.glyphs)", symbol: "questionmark.circle")
                    }
                case .moving:
                    vm.gesture.posX = min(max(v.location.x / size.width, 0.05), 0.95)
                    vm.gesture.posY = min(max(v.location.y / size.height, 0.08), 0.92)
                case .deciding:
                    vm.route = .gestures      // 轻点打开配置
                case .idle: break
                }
                phase = .idle; points = []; recognized = []; matched = nil; livePos = nil
            }
    }
}
