import SwiftUI

/// 划词浮层：选中网页文本后弹出，提供 复制 / 翻译 / 搜索 / BigBang 文本选取。
struct SelectionToolbar: View {
    @EnvironmentObject var vm: BrowserViewModel
    @State private var showTranslation = false
    @State private var showBigBang = false

    var body: some View {
        VStack(spacing: 10) {
            // 操作栏
            HStack(spacing: 0) {
                action("复制", "doc.on.doc") { dismiss() }
                divider
                action("翻译", "character.bubble") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showTranslation = true }
                }
                divider
                action("搜索", "magnifyingglass") {
                    vm.open(url: vm.selectionText); dismiss()
                }
                divider
                action("文本选取", "wand.and.stars") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showBigBang = true }
                }
            }
            .frame(height: 44)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: Theme.Size.hairline))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)

            // 翻译卡片
            if showTranslation {
                translationCard.transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            // BigBang 文本选取
            if showBigBang {
                bigBangCard.transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
        )
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { vm.showSelectionToolbar = false }
    }

    private var divider: some View {
        Rectangle().fill(Color.black.opacity(0.08)).frame(width: Theme.Size.hairline, height: 22)
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: { Haptics.light(); run() }) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(title).font(.system(size: 10))
            }
            .foregroundStyle(Theme.Colors.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
        }
        .buttonStyle(PressableStyle())
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("自动检测 → 中文").font(.system(size: 12)).foregroundStyle(Theme.Colors.secondaryText)
                Spacer()
                Image(systemName: "speaker.wave.2").font(.system(size: 13)).foregroundStyle(Theme.Colors.accent)
            }
            Text(vm.selectionText).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.Colors.primaryText)
            Hairline()
            Text("Legend of Qin").font(.system(size: 16)).foregroundStyle(Theme.Colors.accent)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }

    /// BigBang：把选中文本拆成可点选的词块
    private var bigBangCard: some View {
        let tokens = ["天行", "九歌", "第", "1", "集", "超清", "HD"]
        return VStack(alignment: .leading, spacing: 10) {
            Text("文本选取").font(.system(size: 12)).foregroundStyle(Theme.Colors.secondaryText)
            FlowChips(tokens: tokens)
            HStack(spacing: Theme.Spacing.l) {
                chipAction("复制", "doc.on.doc")
                chipAction("翻译", "character.bubble")
                chipAction("搜索", "magnifyingglass")
                chipAction("分词", "scissors")
            }
            .padding(.top, 2)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
    }

    private func chipAction(_ t: String, _ s: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: s).font(.system(size: 15)).foregroundStyle(Theme.Colors.accent)
            Text(t).font(.system(size: 10)).foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 简单的横向自动换行词块
private struct FlowChips: View {
    let tokens: [String]
    @State private var selected: Set<Int> = [0, 1]
    var body: some View {
        FlexLayout(spacing: 8) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { i, token in
                Text(token)
                    .font(.system(size: 15))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(selected.contains(i) ? Theme.Colors.accent : Theme.Colors.groupedBackground,
                                in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(selected.contains(i) ? .white : Theme.Colors.primaryText)
                    .onTapGesture {
                        if selected.contains(i) { selected.remove(i) } else { selected.insert(i) }
                    }
            }
        }
    }
}

/// 极简流式布局
struct FlexLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
