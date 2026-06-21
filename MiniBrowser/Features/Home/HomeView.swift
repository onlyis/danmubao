import SwiftUI

/// 主页 / 新标签页：顶部地址栏样式搜索框 + 常用网站宫格。
/// 点击搜索原地把搜索栏转成输入框（不弹窗），下方出现搜索引擎图标行 + 建议列表。
struct HomeView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @State private var searching = false
    @State private var query = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)

    /// 壁纸偏好浅色文字时主页文字改白（搜索态用常规背景，不套白字）
    private var lightText: Bool { !searching && vm.wallpaper != .none && vm.wallpaper.prefersLightText }

    var body: some View {
        VStack(spacing: 0) {
            InlineSearchBar(searching: $searching, query: $query, onWallpaper: lightText,
                            onSubmit: submit, onCancel: exitSearch)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, searching ? Theme.Spacing.s : Theme.Spacing.xl)

            if searching {
                engineRow
                SearchSuggestionList(query: query, onPick: submit)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                        ForEach(vm.quickLinks) { link in
                            QuickLinkCell(link: link, lightText: lightText)
                        }
                        AddQuickLinkCell()
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    Spacer(minLength: 80)
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
    }

    /// 搜索引擎图标行：点击切换默认引擎，随后输入即用该引擎搜索。
    private var engineRow: some View {
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
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
        }
        .frame(height: 74)
    }

    private func submit(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        vm.recordSearch(t)
        vm.open(url: t, title: t)
        exitSearch()
    }
    private func exitSearch() {
        query = ""
        withAnimation(.easeOut(duration: 0.15)) { searching = false }
    }
}

/// 顶部搜索栏：未搜索时是按钮（盾牌 + 占位 + 二维码），点击原地变为输入框。
private struct InlineSearchBar: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Binding var searching: Bool
    @Binding var query: String
    var onWallpaper: Bool
    var onSubmit: (String) -> Void
    var onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: searching ? "magnifyingglass" : "shield.lefthalf.filled")
                    .font(.system(size: searching ? 16 : 18))
                    .foregroundStyle(searching ? Theme.Colors.secondaryText
                                     : (vm.isAdBlockOn ? Theme.Colors.safe : Theme.Colors.secondaryText))

                if searching {
                    TextField("搜索或输入网址", text: $query)
                        .focused($focused)
                        .font(.system(size: 16))
                        .submitLabel(.go)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { onSubmit(query) }
                        .toolbar {
                            // 键盘上方 URL 助手栏：快捷输入常用片段
                            ToolbarItemGroup(placement: .keyboard) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(["https://", "www.", ".com", ".cn", ".net", "/"], id: \.self) { frag in
                                            Button(frag) { query += frag }
                                                .font(.system(size: 14, weight: .medium))
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
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
                } else {
                    Text("搜索或输入网址")
                        .font(.system(size: 16))
                        .foregroundStyle(onWallpaper ? Color.white.opacity(0.85) : Theme.Colors.tertiaryText)
                    Spacer()
                    Image(systemName: "qrcode")
                        .font(.system(size: 19))
                        .foregroundStyle(onWallpaper ? Color.white.opacity(0.85) : Theme.Colors.secondaryText)
                        .onTapGesture { vm.route = .qrScanner }
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: Theme.Size.searchBarHeight)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(onWallpaper && !searching ? AnyShapeStyle(.ultraThinMaterial)
                          : AnyShapeStyle(Theme.Colors.groupedBackground))
            }
            .contentShape(Rectangle())
            .onTapGesture { if !searching { enterSearch() } }

            if searching {
                Button("取消") { focused = false; onCancel() }
                    .font(.system(size: 16))
            }
        }
    }

    private func enterSearch() {
        Haptics.light()
        withAnimation(.easeOut(duration: 0.15)) { searching = true }
        // 等输入框出现后再聚焦弹键盘
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
    }
}

/// 搜索态下方：搜索历史 chips + 剪贴板 + 历史记录(favicon+URL) + 搜索建议。
private struct SearchSuggestionList: View {
    @EnvironmentObject var vm: BrowserViewModel
    let query: String
    var onPick: (String) -> Void
    private let base = ["天行九歌", "github trending", "swiftui 教程", "天气预报"]

    /// 仅用 hasURLs 探测（不触发系统粘贴提示），真正读取放到用户点击时。
    private var hasClipURL: Bool { UIPasteboard.general.hasURLs }
    private var suggestions: [String] {
        query.isEmpty ? base : base.filter { $0.localizedCaseInsensitiveContains(query) } + [query]
    }
    /// 浏览历史（扁平、去重 url、按 query 过滤，取前 8）
    private var historyItems: [HistoryItem] {
        var seen = Set<String>()
        let all = vm.library.history.flatMap(\.items).filter { seen.insert($0.url).inserted }
        let filtered = query.isEmpty ? all : all.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.url.localizedCaseInsensitiveContains(query)
        }
        return Array(filtered.prefix(8))
    }

    var body: some View {
        List {
            // 搜索历史 chips（query 为空时）
            if query.isEmpty && !vm.searchHistory.isEmpty {
                Section {
                    chipsRow
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            }

            if hasClipURL {
                Section {
                    Button {
                        if let u = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string { onPick(u) }
                    } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            Image(systemName: "doc.on.clipboard").foregroundStyle(Theme.Colors.accent)
                            Text("打开剪贴板中的网址").font(.system(size: 15)).foregroundStyle(Theme.Colors.primaryText)
                        }
                    }
                }
            }

            if !historyItems.isEmpty {
                Section(query.isEmpty ? "历史记录" : "相关历史") {
                    ForEach(historyItems) { item in
                        Button { onPick(item.url) } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                SiteIconSmall(glyph: item.glyph, color: item.color)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.system(size: 15)).foregroundStyle(Theme.Colors.primaryText).lineLimit(1)
                                    Text(item.url).font(.system(size: 12)).foregroundStyle(Theme.Colors.secondaryText).lineLimit(1)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }

            Section("搜索建议") {
                ForEach(suggestions, id: \.self) { s in
                    Button { onPick(s) } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Theme.Colors.tertiaryText)
                            Text(s).font(.system(size: 15)).foregroundStyle(Theme.Colors.primaryText)
                            Spacer()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    /// 搜索历史 chips：左侧清空按钮 + 横向滚动的可点 chip（长按删单条）
    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button { vm.clearSearchHistory() } label: {
                    Image(systemName: "trash").font(.system(size: 15)).foregroundStyle(Theme.Colors.secondaryText)
                }
                ForEach(vm.searchHistory, id: \.self) { q in
                    Button { onPick(q) } label: {
                        Text(q).font(.system(size: 13)).foregroundStyle(Theme.Colors.primaryText)
                            .lineLimit(1)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.Colors.groupedBackground, in: Capsule())
                    }
                    .contextMenu {
                        Button(role: .destructive) { vm.removeSearch(q) } label: { Label("删除", systemImage: "trash") }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// 单个快捷入口
struct QuickLinkCell: View {
    @EnvironmentObject var vm: BrowserViewModel
    let link: QuickLink
    var lightText: Bool = false

    var body: some View {
        Button {
            Haptics.light()
            vm.open(url: link.url, title: link.title)
        } label: {
            VStack(spacing: 6) {
                BrandIcon(link: link)
                Text(link.title)
                    .font(.system(size: 12))
                    .foregroundStyle(lightText ? .white : Theme.Colors.primaryText)
                    .shadow(color: lightText ? .black.opacity(0.25) : .clear, radius: 2, y: 1)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button { vm.open(url: link.url, title: link.title) } label: { Label("打开", systemImage: "safari") }
            Button { vm.open(url: link.url, title: link.title) } label: { Label("在新标签页打开", systemImage: "plus.square.on.square") }
            Button { } label: { Label("编辑", systemImage: "pencil") }
            Button { } label: { Label("更换图标", systemImage: "photo") }
            Divider()
            Button(role: .destructive) {
                vm.quickLinks.removeAll { $0.id == link.id }
            } label: { Label("删除", systemImage: "trash") }
        }
    }
}

/// 添加快捷入口
private struct AddQuickLinkCell: View {
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.Colors.separator, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                .frame(width: Theme.Size.quickLinkIcon, height: Theme.Size.quickLinkIcon)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }
            Text("添加")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.tertiaryText)
        }
    }
}
