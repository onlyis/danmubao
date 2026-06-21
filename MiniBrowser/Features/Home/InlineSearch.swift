import SwiftUI

/// 统一的内联搜索视图：输入框 + 搜索引擎行 + 历史/建议。主页与浏览态共用，样式一致。
struct InlineSearchView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @State private var query = ""
    var onSubmit: (String) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SearchInputField(query: $query, onSubmit: submit, onCancel: onCancel)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.s)
            SearchEngineRow()
            SearchSuggestionList(query: query, onPick: submit)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    private func submit(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        onSubmit(t)
    }
}

/// 搜索输入框：白底 + 强调色细描边 + 取消 + 键盘上方 URL 助手栏。
private struct SearchInputField: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Binding var query: String
    var onSubmit: (String) -> Void
    var onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16)).foregroundStyle(Theme.Colors.secondaryText)
                TextField("搜索或输入网址", text: $query)
                    .focused($focused)
                    .font(.system(size: 16))
                    .submitLabel(.go)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { onSubmit(query) }
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(["https://", "www.", ".com", ".cn", ".net", "/"], id: \.self) { frag in
                                        Button(frag) { query += frag }
                                            .font(.system(size: 14, weight: .medium))
                                            .buttonStyle(.bordered).controlSize(.small)
                                            .tint(Theme.Colors.secondaryText)
                                    }
                                }
                            }
                        }
                    }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Colors.tertiaryText)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: Theme.Size.searchBarHeight)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.Colors.card)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(Theme.Colors.accent.opacity(0.5), lineWidth: 1.5)
            }

            Button("取消") { focused = false; onCancel() }.font(.system(size: 16))
        }
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { focused = true } }
    }
}

/// 搜索引擎图标行：点击切换默认引擎。
struct SearchEngineRow: View {
    @EnvironmentObject var vm: BrowserViewModel
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(vm.allSearchEngines) { e in
                    let isSel = e.id == vm.searchEngine.id
                    Button { Haptics.light(); vm.searchEngine = e } label: {
                        VStack(spacing: 4) {
                            SiteIcon(glyph: e.glyph, color: e.color, size: 40, corner: 11)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .strokeBorder(Theme.Colors.accent, lineWidth: isSel ? 2.5 : 0)
                                )
                            Text(e.name).font(.system(size: 10))
                                .foregroundStyle(isSel ? Theme.Colors.accent : Theme.Colors.secondaryText)
                                .lineLimit(1)
                        }
                        .frame(width: 54)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.l).padding(.vertical, Theme.Spacing.s)
        }
        .frame(height: 74)
    }
}

/// 搜索内容区：搜索历史 chips + 剪贴板 + 历史记录(favicon+URL) + 搜索建议。
struct SearchSuggestionList: View {
    @EnvironmentObject var vm: BrowserViewModel
    let query: String
    var onPick: (String) -> Void
    private let base = ["天行九歌", "github trending", "swiftui 教程", "天气预报"]

    private var hasClipURL: Bool { UIPasteboard.general.hasURLs }
    private var suggestions: [String] {
        query.isEmpty ? base : base.filter { $0.localizedCaseInsensitiveContains(query) } + [query]
    }
    private var historyItems: [HistoryItem] {
        var seen = Set<String>()
        let all = vm.library.history.flatMap(\.items).filter { seen.insert($0.url).inserted }
        let filtered = query.isEmpty ? all : all.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.url.localizedCaseInsensitiveContains(query)
        }
        return Array(filtered.prefix(8))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if query.isEmpty && !vm.searchHistory.isEmpty {
                    chipsSection
                }
                if hasClipURL {
                    sectionCard {
                        Button {
                            if let u = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string { onPick(u) }
                        } label: {
                            rowLabel(icon: "doc.on.clipboard", title: "打开剪贴板中的网址", subtitle: nil, accent: true)
                        }
                    }
                }
                if !historyItems.isEmpty {
                    section(query.isEmpty ? "历史记录" : "相关历史") {
                        ForEach(Array(historyItems.enumerated()), id: \.element.id) { i, item in
                            Button { onPick(item.url) } label: { historyRow(item) }
                            if i < historyItems.count - 1 { rowDivider }
                        }
                    }
                }
                section("搜索建议") {
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { i, s in
                        Button { onPick(s) } label: {
                            rowLabel(icon: "magnifyingglass", title: s, subtitle: nil, accent: false)
                        }
                        if i < suggestions.count - 1 { rowDivider }
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - 组件
    private var chipsSection: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { vm.clearSearchHistory() } label: {
                Image(systemName: "trash").font(.system(size: 15)).foregroundStyle(Theme.Colors.secondaryText)
                    .frame(width: 28, height: 28)
            }
            FlowLayout(spacing: 8) {
                ForEach(vm.searchHistory, id: \.self) { q in
                    Button { onPick(q) } label: {
                        Text(q).font(.system(size: 13)).foregroundStyle(Theme.Colors.primaryText).lineLimit(1)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.Colors.groupedBackground, in: Capsule())
                    }
                    .contextMenu {
                        Button(role: .destructive) { vm.removeSearch(q) } label: { Label("删除", systemImage: "trash") }
                    }
                }
            }
        }
    }

    @ViewBuilder private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.Colors.secondaryText)
                .padding(.leading, 4)
            sectionCard { VStack(spacing: 0) { content() } }
        }
    }
    @ViewBuilder private func sectionCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }
    private var rowDivider: some View {
        Rectangle().fill(Theme.Colors.separator).frame(height: Theme.Size.hairline).padding(.leading, 34)
    }
    private func rowLabel(icon: String, title: String, subtitle: String?, accent: Bool) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: icon).font(.system(size: 15))
                .foregroundStyle(accent ? Theme.Colors.accent : Theme.Colors.tertiaryText).frame(width: 22)
            Text(title).font(.system(size: 15)).foregroundStyle(Theme.Colors.primaryText).lineLimit(1)
            Spacer()
        }
        .frame(height: 44)
    }
    private func historyRow(_ item: HistoryItem) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            SiteIconSmall(glyph: item.glyph, color: item.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 15)).foregroundStyle(Theme.Colors.primaryText).lineLimit(1)
                Text(item.url).font(.system(size: 12)).foregroundStyle(Theme.Colors.secondaryText).lineLimit(1)
            }
            Spacer()
        }
        .frame(height: 52)
    }
}

/// 简单流式布局：子视图自动换行排列。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
