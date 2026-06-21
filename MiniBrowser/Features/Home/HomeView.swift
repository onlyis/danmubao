import SwiftUI

/// 主页 / 新标签页：顶部搜索栏 + 双页（常用宫格 / 网址导航目录）。
/// 点击搜索栏弹出统一的内联搜索（与浏览态共用 InlineSearchView）。
struct HomeView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @State private var homePage = 0
    @State private var showAddLink = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)
    private var lightText: Bool { vm.wallpaper != .none && vm.wallpaper.prefersLightText }

    var body: some View {
        VStack(spacing: 0) {
            HomeSearchButton(onWallpaper: lightText)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xl)

            TabView(selection: $homePage) {
                quickLinksPage.tag(0)
                NavDirectoryView(lightText: lightText).tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            .frame(maxHeight: .infinity)
        }
    }

    private var quickLinksPage: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                ForEach(vm.quickLinks) { link in
                    QuickLinkCell(link: link, lightText: lightText)
                }
                Button { showAddLink = true } label: { AddQuickLinkCell(lightText: lightText) }
                    .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, Theme.Spacing.l)
            Spacer(minLength: 80)
        }
        .sheet(isPresented: $showAddLink) { AddQuickLinkSheet() }
    }
}

/// 添加快捷网站
private struct AddQuickLinkSheet: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") { TextField("名称（可选）", text: $name) }
                Section("网址") {
                    TextField("example.com", text: $url)
                        .autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
                }
            }
            .navigationTitle("添加快捷网站").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加") { vm.addQuickLink(title: name, url: url); dismiss() }
                        .fontWeight(.semibold).disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(260)])
    }
}

/// 主页顶部搜索栏（盾牌 + 占位 + 二维码），点击弹出统一搜索。
private struct HomeSearchButton: View {
    @EnvironmentObject var vm: BrowserViewModel
    var onWallpaper: Bool

    var body: some View {
        Button { Haptics.light(); vm.showSearch = true } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 18))
                    .foregroundStyle(vm.isAdBlockOn ? Theme.Colors.safe : Theme.Colors.secondaryText)
                Text("搜索或输入网址")
                    .font(.system(size: 16))
                    .foregroundStyle(onWallpaper ? Color.white.opacity(0.85) : Theme.Colors.tertiaryText)
                Spacer()
                Image(systemName: "qrcode")
                    .font(.system(size: 19))
                    .foregroundStyle(onWallpaper ? Color.white.opacity(0.85) : Theme.Colors.secondaryText)
                    .onTapGesture { vm.route = .qrScanner }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .frame(height: Theme.Size.searchBarHeight)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(onWallpaper ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Theme.Colors.groupedBackground))
            }
        }
        .buttonStyle(.plain)
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
    var lightText: Bool = false
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(lightText ? Color.white.opacity(0.5) : Theme.Colors.separator,
                              style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                .frame(width: Theme.Size.quickLinkIcon, height: Theme.Size.quickLinkIcon)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(lightText ? .white : Theme.Colors.tertiaryText)
                }
            Text("添加")
                .font(.system(size: 12))
                .foregroundStyle(lightText ? .white : Theme.Colors.tertiaryText)
        }
    }
}
