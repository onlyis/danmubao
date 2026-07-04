import SwiftUI

/// 主页 / 新标签页：顶部搜索栏 + 双页（常用宫格 / 网址导航目录）。
/// 点击搜索栏弹出统一的内联搜索（与浏览态共用 InlineSearchView）。
struct HomeView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @State private var homePage = 0
    @State private var showAddLink = false
    /// 正在拖动重排的快捷入口（长按拾起 → 拖到目标位置前插入）
    @State private var draggingLink: QuickLink?

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
                // 第二屏「网址导航目录」：由设置开关控制是否显示（默认显示）。
                if vm.showNavDirectory {
                    NavDirectoryView(lightText: lightText).tag(1)
                }
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
                        .opacity(draggingLink?.id == link.id ? 0.35 : 1)
                        // 长按拾起拖动重排（与标签网格同一交互）；轻点仍打开、长按仍弹出菜单
                        .onDrag {
                            draggingLink = link
                            return NSItemProvider(object: link.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text],
                                delegate: QuickLinkDropDelegate(item: link, dragging: $draggingLink, vm: vm))
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

/// 快捷入口拖动重排的 drop 委托：把拖动项移动到悬停项之前（mutate vm.quickLinks → didSet 落盘）。
private struct QuickLinkDropDelegate: DropDelegate {
    let item: QuickLink
    @Binding var dragging: QuickLink?
    let vm: BrowserViewModel

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging.id != item.id,
              let from = vm.quickLinks.firstIndex(where: { $0.id == dragging.id }),
              let to = vm.quickLinks.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            let moved = vm.quickLinks.remove(at: from)
            vm.quickLinks.insert(moved, at: to > from ? to - 1 : to)
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
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
        // 用 onTapGesture 而非 Button：与标签卡片同一模式，避免在「分页 TabView + ScrollView + 拖动重排 + contextMenu」
        // 多手势叠加下 Button 的点击被吞掉（导致「点了快捷入口不加载页面」）。
        VStack(spacing: 6) {
            BrandIcon(link: link)
            Text(link.title)
                .font(.system(size: 12))
                .foregroundStyle(lightText ? .white : Theme.Colors.primaryText)
                .shadow(color: lightText ? .black.opacity(0.25) : .clear, radius: 2, y: 1)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { Haptics.light(); vm.open(url: link.url, title: link.title) }
        .contextMenu {
            Button { vm.open(url: link.url, title: link.title) } label: { Label("打开", systemImage: "safari") }
            Button { vm.openInNewTab(url: link.url) } label: { Label("在新标签页打开", systemImage: "plus.square.on.square") }
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
