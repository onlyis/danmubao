import SwiftUI

/// 主页 / 新标签页：顶部地址栏样式搜索框 + 常用网站宫格。极简、无信息流。
struct HomeView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @State private var pullOffset: CGFloat = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 4)

    /// 壁纸偏好浅色文字时，主页文字改用白色以保证清晰
    private var lightText: Bool { vm.wallpaper != .none && vm.wallpaper.prefersLightText }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 顶部搜索栏（地址栏样式：盾牌 + 占位文案 + 二维码）
                HomeSearchBar(onWallpaper: lightText)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.top, Theme.Spacing.s)
                    .padding(.bottom, Theme.Spacing.xl)

                // 常用网站宫格
                LazyVGrid(columns: columns, spacing: Theme.Spacing.l) {
                    ForEach(vm.quickLinks) { link in
                        QuickLinkCell(link: link, lightText: lightText)
                    }
                    AddQuickLinkCell()
                }
                .padding(.horizontal, Theme.Spacing.l)

                Spacer(minLength: 80)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            // 主页下拉触发搜索聚焦
            vm.showSearch = true
        }
    }
}

/// 主页顶部搜索栏
private struct HomeSearchBar: View {
    @EnvironmentObject var vm: BrowserViewModel
    var onWallpaper: Bool = false

    var body: some View {
        Button {
            Haptics.light()
            vm.showSearch = true
        } label: {
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
                if onWallpaper {
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .fill(.ultraThinMaterial)
                } else {
                    RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                        .fill(Theme.Colors.groupedBackground)
                }
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
