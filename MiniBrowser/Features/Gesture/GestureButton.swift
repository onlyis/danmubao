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
    private var inToolbar: Bool { vm.gesture.placement == .toolbar }
    private var radius: CGFloat {
        let base: CGFloat = inToolbar ? 19 : 27   // 工具栏模式更像图标
        return base * (inToolbar ? 1 : vm.gesture.buttonSize)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 轨迹与提示（不拦截触摸）
                if phase == .gesturing {
                    trail
                    hud(in: geo.size)
                }
                if isDockedLine {
                    // 贴边停靠：锁成一条边缘线（类似小米边缘手势条），按住拖出即画手势
                    dockedLine
                        .position(dockedLinePosition(in: geo.size))
                        .gesture(drag(in: geo.size))
                } else {
                    button
                        .opacity(restingOpacity(in: geo.size))
                        .position(center(in: geo.size))
                        .gesture(drag(in: geo.size))
                }
            }
            .coordinateSpace(name: coordSpace)
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    // MARK: - 按钮
    @ViewBuilder
    private var button: some View {
        if inToolbar {
            // 工具栏图标：醒目=强调色+细环区分；普通=与其它图标一致（灰、防分心）
            Group {
                if vm.gesture.distinctIcon {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(width: radius * 2, height: radius * 2)
                        .background(Circle().fill(Theme.Colors.accent.opacity(0.12)))
                        .overlay(Circle().strokeBorder(Theme.Colors.accent.opacity(0.45), lineWidth: 1.5))
                } else {
                    Image(systemName: "hand.draw.fill")
                        .font(.system(size: 21))
                        .foregroundStyle(Theme.Colors.toolbarIcon)
                        .frame(width: radius * 2, height: radius * 2)
                }
            }
            .scaleEffect(phase == .gesturing ? 1.15 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: phase)
        } else {
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
    }

    /// 悬浮模式、空闲、且贴到左右边缘 → 锁成边缘线。
    private var isDockedLine: Bool {
        phase == .idle && vm.gesture.placement == .floating
            && (vm.gesture.posX < 0.06 || vm.gesture.posX > 0.94)
    }
    /// 边缘手势线
    private var dockedLine: some View {
        Capsule()
            .fill(Theme.Colors.accent.opacity(0.75))
            .frame(width: 5, height: 52)
            .shadow(color: .black.opacity(0.15), radius: 2)
    }
    private func dockedLinePosition(in size: CGSize) -> CGPoint {
        let x: CGFloat = vm.gesture.posX < 0.5 ? 3 : size.width - 3
        let y = min(max(vm.gesture.posY * size.height, 60), size.height - 60)
        return CGPoint(x: x, y: y)
    }

    /// 停靠在边缘且空闲时半透明（露一部分在视野内）。
    private func restingOpacity(in size: CGSize) -> CGFloat {
        guard phase == .idle, vm.gesture.placement == .floating else { return 1 }
        let x = vm.gesture.posX * size.width
        return (x < radius || x > size.width - radius) ? 0.5 : 1
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
        // 工具栏图标：定位到 .gesture 在工具栏中的槽位（等分），不可移动
        if inToolbar, let idx = vm.toolbarItems.firstIndex(of: .gesture) {
            let count = max(vm.toolbarItems.count, 1)
            let x = (CGFloat(idx) + 0.5) / CGFloat(count) * size.width
            let y = size.height - Self.safeBottomInset - Theme.Size.toolbarHeight / 2
            return CGPoint(x: x, y: y)
        }
        if phase == .moving, let livePos { return clamp(livePos, in: size) }
        return clamp(CGPoint(x: vm.gesture.posX * size.width, y: vm.gesture.posY * size.height), in: size)
    }
    /// 悬浮模式：水平允许约 60% 拖出边缘（保留一部分在视野内），竖直留常规边距。
    private func clamp(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let mx = radius * 0.4
        let my = radius + 6
        return CGPoint(x: min(max(p.x, mx), size.width - mx),
                       y: min(max(p.y, my), size.height - my))
    }

    /// 真实底部安全区高度（home indicator）：覆盖层 ignoresSafeArea 后 GeometryReader 读不到，
    /// 这里取主窗口 safeAreaInsets，保证工具栏槽位 y 在各机型精确对齐。
    @MainActor private static var safeBottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.safeAreaInsets.bottom ?? 34
    }

    // MARK: - 手势
    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordSpace))
            .onChanged { v in
                switch phase {
                case .idle:
                    phase = .deciding
                    points = [v.location]
                    // 仅悬浮模式可长按拾起移动；底部居中固定不动
                    if vm.gesture.placement == .floating {
                        let work = DispatchWorkItem {
                            if phase == .deciding { phase = .moving; livePos = v.location; Haptics.soft() }
                        }
                        liftWork = work
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
                    }
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
                    recognized = GestureRecognizer.recognize(points, toleranceDeg: vm.gesture.straightnessToleranceDeg, detectCircle: vm.gesture.enableCircle)
                    matched = vm.matchGesture(recognized)
                case .moving:
                    livePos = v.location
                }
            }
            .onEnded { v in
                liftWork?.cancel()
                switch phase {
                case .gesturing:
                    let dirs = GestureRecognizer.recognize(points, toleranceDeg: vm.gesture.straightnessToleranceDeg, detectCircle: vm.gesture.enableCircle)
                    if let action = vm.matchGesture(dirs) {
                        vm.perform(action)
                    } else if !dirs.isEmpty {
                        vm.showToast("未匹配手势 \(dirs.glyphs)", symbol: "questionmark.circle")
                    }
                case .moving:
                    // 贴边停靠：拖近左右边缘时吸附并只露一部分；否则停在落点
                    var x = v.location.x
                    let edge = radius * 1.5
                    if x < edge { x = radius * 0.4 }
                    else if x > size.width - edge { x = size.width - radius * 0.4 }
                    vm.gesture.posX = min(max(x / size.width, 0.0), 1.0)
                    vm.gesture.posY = min(max(v.location.y / size.height, 0.08), 0.92)
                case .deciding:
                    vm.route = .gestures      // 轻点打开配置
                case .idle: break
                }
                phase = .idle; points = []; recognized = []; matched = nil; livePos = nil
            }
    }
}
