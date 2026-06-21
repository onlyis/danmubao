import SwiftUI

/// 工具栏按钮种类（可在「自定义底部工具栏按钮」里排序；gesture 为特色项，需区分对待）。
enum ToolbarItemKind: String, Codable, CaseIterable, Identifiable {
    case back, forward, menu, tabs, home, gesture
    var id: String { rawValue }
    var title: String {
        switch self {
        case .back: return "后退"; case .forward: return "前进"; case .menu: return "菜单"
        case .tabs: return "标签页"; case .home: return "主页"; case .gesture: return "手势按钮"
        }
    }
    var symbol: String {
        switch self {
        case .back: return "chevron.left"; case .forward: return "chevron.right"
        case .menu: return "line.3.horizontal"; case .tabs: return "square.on.square"
        case .home: return "house"; case .gesture: return "hand.draw.fill"
        }
    }
    var isGesture: Bool { self == .gesture }
}

/// 底部固定工具栏：按 `vm.toolbarItems` 顺序渲染，始终可见。
/// `.gesture` 槽位渲染为空占位，由 GestureButton 覆盖层在该位置绘制特色图标并承接画手势。
struct BottomToolbar: View {
    @EnvironmentObject var vm: BrowserViewModel
    var engine: WebEngine?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(vm.toolbarItems) { item in
                button(for: item)
            }
        }
        .frame(height: Theme.Size.toolbarHeight)
        .frame(maxWidth: .infinity)
        .background(
            (vm.isIncognito ? Color(hex: 0x111114) : Theme.Colors.card)
                .overlay(alignment: .top) { Hairline() }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private func button(for item: ToolbarItemKind) -> some View {
        switch item {
        case .back:    ToolbarButton(symbol: "chevron.left", enabled: vm.isBrowsing) { vm.back() }
        case .forward: ForwardButton(engine: engine) { vm.forward() }
        case .menu:    ToolbarButton(symbol: "line.3.horizontal") { vm.showMenu = true }
        case .tabs:    TabsButton(count: vm.tabCount) { vm.showTabs = true }
        case .home:    ToolbarButton(symbol: vm.isBrowsing ? "house" : "house.fill") { vm.goHome() }
        case .gesture: Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)  // 占位，覆盖层绘制
        }
    }
}

/// 前进按钮：响应当前标签引擎的 canGoForward
private struct ForwardButton: View {
    let engine: WebEngine?
    let action: () -> Void
    var body: some View {
        if let engine {
            ForwardButtonInner(engine: engine, action: action)
        } else {
            DisabledForward()
        }
    }
}
private struct ForwardButtonInner: View {
    @ObservedObject var engine: WebEngine
    let action: () -> Void
    var body: some View {
        ToolbarButton(symbol: "chevron.right", enabled: engine.canGoForward, action: action)
    }
}
private struct DisabledForward: View {
    var body: some View { ToolbarButton(symbol: "chevron.right", enabled: false) {} }
}

private struct ToolbarButton: View {
    var symbol: String
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: { if enabled { Haptics.light(); action() } }) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(enabled ? Theme.Colors.toolbarIcon : Theme.Colors.toolbarDisabled)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// 标签页按钮：方框中显示当前标签数量
private struct TabsButton: View {
    var count: Int
    var action: () -> Void

    var body: some View {
        Button(action: { Haptics.light(); action() }) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Theme.Colors.toolbarIcon, lineWidth: 2)
                .frame(width: 24, height: 24)
                .overlay {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Colors.toolbarIcon)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

/// 轻按压反馈
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.45 : 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

enum Haptics {
    static func light() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.impactOccurred()
    }
    static func soft() {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.impactOccurred()
    }
}
