import SwiftUI
import UniformTypeIdentifiers

/// 可编辑功能宫格：长按进入编辑态 → 删除（角标）/ 拖动重排 / 添加其它功能。
/// 菜单（`MainMenuSheet`）与盾牌控制面板（`ControlPanelSheet`）复用同一组件，避免重复实现。
/// - `titles` 绑定到 VM 的持久化顺序数组（其 didSet 落盘）。
/// - `pool` 为可添加的完整目录；`isOn`/`perform` 按标题派发，复用 `vm.actionIsOn`/`vm.performMenuAction`。
struct EditableActionGrid: View {
    @Binding var titles: [String]
    let pool: [MenuAction]
    /// 跨页已用标题集合（分页菜单传所有页的并集，避免重复添加）；nil = 用本页 `titles`。
    var usedTitles: [String]? = nil
    var columns: Int = 4
    let isOn: (String) -> Bool
    let perform: (String) -> Void

    @Binding var editing: Bool
    @State private var showAdd = false
    @State private var dragging: String?

    private var grid: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 8), count: columns) }
    private var actions: [MenuAction] { titles.compactMap { t in pool.first { $0.title == t } } }
    private var addable: [MenuAction] {
        let used = Set(usedTitles ?? titles)
        return pool.filter { !used.contains($0.title) }
    }

    var body: some View {
        LazyVGrid(columns: grid, spacing: 18) {
            ForEach(actions, id: \.title) { item in
                ActionCell(item: item, isOn: isOn(item.title), editing: editing,
                           onTap: { editing ? () : perform(item.title) },
                           onDelete: { remove(item.title) })
                    .opacity(dragging == item.title ? 0.35 : 1)
                    .onLongPressGesture(minimumDuration: 0.4) {
                        if !editing { Haptics.soft(); withAnimation(.easeOut(duration: 0.15)) { editing = true } }
                    }
                    .onDrag(if: editing) {
                        dragging = item.title
                        return NSItemProvider(object: item.title as NSString)
                    }
                    .onDrop(of: [.text], delegate: ActionDropDelegate(
                        item: item.title, titles: $titles, dragging: $dragging, active: editing))
            }
            if editing && !addable.isEmpty {
                AddCell { showAdd = true }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddActionSheet(pool: addable) { add($0) }
        }
    }

    private func add(_ title: String) {
        guard !titles.contains(title) else { return }
        titles.append(title)
    }
    private func remove(_ title: String) {
        guard titles.count > 1 else { return }   // 至少留一个
        withAnimation { titles.removeAll { $0 == title } }
    }
}

/// 仅在 `active` 时附加 onDrag 的便捷修饰。
private extension View {
    @ViewBuilder func onDrag(if active: Bool, _ provider: @escaping () -> NSItemProvider) -> some View {
        if active { self.onDrag(provider) } else { self }
    }
}

/// 拖动重排：把拖动项移动到悬停项之前（操作绑定的 titles 数组）。
private struct ActionDropDelegate: DropDelegate {
    let item: String
    @Binding var titles: [String]
    @Binding var dragging: String?
    let active: Bool

    func dropEntered(info: DropInfo) {
        guard active, let dragging, dragging != item,
              let from = titles.firstIndex(of: dragging),
              let to = titles.firstIndex(of: item) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            let moved = titles.remove(at: from)
            titles.insert(moved, at: to > from ? to - 1 : to)
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: active ? .move : .cancel) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

/// 单个功能格（与原 MenuCell 视觉一致：图标方块 + 开关角标 + 编辑态删除角标）。
struct ActionCell: View {
    let item: MenuAction
    var isOn: Bool
    var editing: Bool
    var onTap: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Button { Haptics.light(); onTap() } label: {
            VStack(spacing: 7) {
                Image(systemName: item.symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(isOn ? .white : Theme.Colors.primaryText)
                    .frame(width: 50, height: 50)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isOn ? Theme.Colors.accent : Theme.Colors.groupedBackground))
                    .overlay(alignment: .bottomTrailing) {
                        if item.isToggle && !editing {
                            Capsule().fill(isOn ? Theme.Colors.safe : Color.gray.opacity(0.45))
                                .frame(width: 22, height: 13)
                                .overlay(Circle().fill(.white).frame(width: 10, height: 10).offset(x: isOn ? 4.5 : -4.5))
                                .overlay(Capsule().strokeBorder(Theme.Colors.card, lineWidth: 1.5))
                                .offset(x: 5, y: 5)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if editing {
                            Button(action: { Haptics.light(); onDelete() }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 19))
                                    .foregroundStyle(.white, Theme.Colors.danger)
                                    .background(Circle().fill(.white).frame(width: 15, height: 15))
                            }
                            .buttonStyle(.plain)
                            .offset(x: -6, y: -6)
                        }
                    }
                Text(item.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PressableStyle())
        // 编辑态轻微抖动，提示可拖动/删除
        .modifier(WiggleEffect(active: editing))
    }
}

/// 「添加」占位格。
private struct AddCell: View {
    var action: () -> Void
    var body: some View {
        Button(action: { Haptics.light(); action() }) {
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.Colors.separator, style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                    .frame(width: 50, height: 50)
                    .overlay(Image(systemName: "plus").font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.Colors.tertiaryText))
                Text("添加").font(.system(size: 11)).foregroundStyle(Theme.Colors.tertiaryText)
            }
        }
        .buttonStyle(PressableStyle())
    }
}

/// 添加功能选择：grid 宫格呈现尚未加入的功能，点击加入当前页。
private struct AddActionSheet: View {
    let pool: [MenuAction]
    var onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(pool, id: \.title) { item in
                        Button {
                            Haptics.light(); onAdd(item.title); dismiss()
                        } label: {
                            VStack(spacing: 7) {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.Colors.primaryText)
                                    .frame(width: 50, height: 50)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Theme.Colors.groupedBackground))
                                Text(item.title).font(.system(size: 11))
                                    .foregroundStyle(Theme.Colors.secondaryText).lineLimit(1)
                            }
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .navigationTitle("添加功能")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() }.fontWeight(.semibold) } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 编辑态的轻微摆动效果（纯装饰，提示可编辑）。
private struct WiggleEffect: ViewModifier {
    let active: Bool
    @State private var phase = false
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(active ? (phase ? 1.4 : -1.4) : 0))
            .animation(active ? .easeInOut(duration: 0.16).repeatForever(autoreverses: true) : .default, value: phase)
            .onAppear { if active { phase = true } }
            .onChange(of: active) { _, on in phase = on }
    }
}
