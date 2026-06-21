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

/// 搜索态下方：剪贴板网址 + 搜索建议（点击即用当前引擎跳转）。
private struct SearchSuggestionList: View {
    let query: String
    var onPick: (String) -> Void
    private let base = ["天行九歌", "github trending", "swiftui 教程", "天气预报"]

    /// 仅用 hasURLs 探测（不触发系统粘贴提示），真正读取放到用户点击时。
    private var hasClipURL: Bool { UIPasteboard.general.hasURLs }
    private var items: [String] {
        query.isEmpty ? base : base.filter { $0.localizedCaseInsensitiveContains(query) } + [query]
    }

    var body: some View {
        List {
            if hasClipURL {
                Section {
                    Button {
                        if let u = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string {
                            onPick(u)
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            Image(systemName: "doc.on.clipboard").foregroundStyle(Theme.Colors.accent)
                            Text("打开剪贴板中的网址").font(.system(size: 15)).foregroundStyle(Theme.Colors.primaryText)
                        }
                    }
                }
            }
            Section("搜索建议") {
                ForEach(items, id: \.self) { s in
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
