import SwiftUI

/// 标签页管理：卡片式缩略图网格 + 顶部栏 + 底部模式切换栏。
struct TabsView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var activeTabs: [Tab] { vm.activeTabs }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Hairline()

            ScrollView {
                if activeTabs.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(activeTabs) { tab in
                            TabCard(tab: tab,
                                    isCurrent: tab.id == vm.currentTabID,
                                    open: { vm.select(tab); dismiss() },
                                    close: { vm.close(tab) })
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
            }

            Hairline()
            bottomBar
        }
        .background((vm.isIncognito ? Color.black : Theme.Colors.background).ignoresSafeArea())
    }

    private var topBar: some View {
        HStack {
            Button("完成") { dismiss() }.font(.system(size: 16, weight: .medium))
            Spacer()
            Text("\(activeTabs.count) 个标签页")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Colors.primaryText)
            Spacer()
            Button { vm.newTab(); dismiss() } label: {
                Image(systemName: "plus").font(.system(size: 18, weight: .medium))
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(height: 50)
    }

    private var bottomBar: some View {
        HStack {
            ModeTab(symbol: "globe", title: "普通", active: !vm.isIncognito) {
                if vm.isIncognito { vm.toggleIncognito() }
            }
            ModeTab(symbol: "eyeglasses", title: "无痕", active: vm.isIncognito) {
                if !vm.isIncognito {
                    vm.toggleIncognito()
                    if vm.incognitoTabs.isEmpty { vm.newTab() }
                }
            }
            Spacer()
            Button { } label: { Image(systemName: "arrow.uturn.backward").font(.system(size: 17)) }
                .foregroundStyle(Theme.Colors.secondaryText)
            Button(role: .destructive) { vm.closeAllActive() } label: {
                Image(systemName: "trash").font(.system(size: 17))
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: 50)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "eyeglasses").font(.system(size: 44)).foregroundStyle(Theme.Colors.incognito)
            Text("无痕浏览").font(.system(size: 17, weight: .semibold))
            Text("关闭所有无痕标签后将清除本次记录").font(.system(size: 13)).foregroundStyle(Theme.Colors.secondaryText)
        }
        .padding(.top, 120)
    }
}

private struct ModeTab: View {
    var symbol: String, title: String, active: Bool, action: () -> Void
    var body: some View {
        Button(action: { Haptics.light(); action() }) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 14))
                Text(title).font(.system(size: 14, weight: active ? .semibold : .regular))
            }
            .foregroundStyle(active ? Theme.Colors.accent : Theme.Colors.secondaryText)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(active ? Theme.Colors.accent.opacity(0.12) : .clear, in: Capsule())
        }
    }
}

private struct TabCard: View {
    @ObservedObject var tab: Tab
    var isCurrent: Bool
    var open: () -> Void
    var close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 缩略图
            ZStack(alignment: .topTrailing) {
                Group {
                    if tab.isHome {
                        Theme.Colors.groupedBackground.overlay {
                            Image(systemName: "house.fill").font(.system(size: 30)).foregroundStyle(Theme.Colors.tertiaryText)
                        }
                    } else {
                        LinearGradient(colors: [tab.tint, tab.tint.opacity(0.6)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay(alignment: .topLeading) {
                                Text(tab.displayTitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.9))
                                    .lineLimit(2).padding(8)
                            }
                    }
                }
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))

                Button(action: { Haptics.light(); close() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
                .padding(6)
            }

            HStack(spacing: 6) {
                SiteIcon(glyph: String(tab.displayTitle.prefix(1)), color: tab.tint, size: 16, corner: 4)
                Text(tab.isHome ? "新标签页" : tab.displayTitle)
                    .font(.system(size: 12)).foregroundStyle(Theme.Colors.primaryText).lineLimit(1)
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
        }
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .strokeBorder(Theme.Colors.accent, lineWidth: isCurrent ? 2 : 0)
        )
        .onTapGesture { Haptics.light(); open() }
        .contextMenu {
            Button { } label: { Label("复制链接", systemImage: "doc.on.doc") }
            Button { } label: { Label("添加书签", systemImage: "bookmark") }
            Button { } label: { Label("分享", systemImage: "square.and.arrow.up") }
            Divider()
            Button(role: .destructive) { close() } label: { Label("关闭", systemImage: "xmark") }
        }
    }
}
