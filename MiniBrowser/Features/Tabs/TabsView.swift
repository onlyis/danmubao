import SwiftUI
import UniformTypeIdentifiers

/// 标签页管理：卡片式缩略图网格 + 顶部栏 + 底部模式切换栏。
struct TabsView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @State private var draggingTab: Tab?

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    private var activeTabs: [Tab] { vm.activeTabs }
    /// 标签管理深灰底（参考 Alook/Safari），区别于主页白底
    private var backdrop: Color { vm.isIncognito ? .black : Color(hex: 0x2C2C2E) }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(Color.white.opacity(0.08))

            ScrollView {
                if activeTabs.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(activeTabs) { tab in
                            TabCard(tab: tab,
                                    isCurrent: tab.id == vm.currentTabID,
                                    open: { vm.select(tab) },
                                    close: { withAnimation(.easeOut(duration: 0.2)) { vm.close(tab) } })
                                // 新建标签从左下角弹出
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.2, anchor: .bottomLeading).combined(with: .opacity),
                                    removal: .scale(scale: 0.4).combined(with: .opacity)))
                                // 拖动重排标签
                                .onDrag {
                                    draggingTab = tab
                                    return NSItemProvider(object: tab.id.uuidString as NSString)
                                }
                                .onDrop(of: [.text], delegate: TabDropDelegate(item: tab, dragging: $draggingTab, vm: vm))
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
            }

            Divider().overlay(Color.white.opacity(0.08))
            bottomBar
        }
        .background(backdrop.ignoresSafeArea())
        .onAppear { vm.captureCurrentThumbnail() }
    }

    private var topBar: some View {
        HStack {
            Color.clear.frame(width: 44, height: 1)
            Spacer()
            Text("\(activeTabs.count) 个标签页")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Button { withAnimation(.easeOut(duration: 0.2)) { vm.closeAllActive() } } label: {
                Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 44)
            .disabled(activeTabs.isEmpty)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(height: 50)
    }

    /// 底部三段式：无痕/普通切换 ｜ 新建 ｜ 完成（参考 Alook）
    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button {
                Haptics.light(); withAnimation { vm.toggleIncognito() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: vm.isIncognito ? "globe" : "eyeglasses")
                    Text(vm.isIncognito ? "普通浏览" : "无痕浏览")
                }
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
            }
            Button {
                Haptics.light()
                vm.newTab()             // 触发 pagePopTrigger（新页面左下角弹出）
                vm.showTabs = false     // 标签管理就地淡出
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(maxWidth: .infinity)
            }
            Button { vm.showTabs = false } label: {
                Text("完成")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 54)
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

/// 拖动重排标签的 drop 委托
private struct TabDropDelegate: DropDelegate {
    let item: Tab
    @Binding var dragging: Tab?
    let vm: BrowserViewModel

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging.id != item.id else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            vm.moveTab(dragging, before: item)
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}

private struct TabCard: View {
    @ObservedObject var tab: Tab
    var isCurrent: Bool
    var open: () -> Void
    var close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 缩略图（更高；不在缩略图内叠加文字）
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumb = tab.thumbnail, !tab.isHome {
                        Image(uiImage: thumb)
                            .resizable().scaledToFill()
                            .frame(maxWidth: .infinity)
                    } else if tab.isHome {
                        Theme.Colors.groupedBackground.overlay {
                            Image(systemName: "house.fill").font(.system(size: 34)).foregroundStyle(Theme.Colors.tertiaryText)
                        }
                    } else {
                        LinearGradient(colors: [tab.tint, tab.tint.opacity(0.6)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))

                Button(action: { Haptics.light(); close() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(6)
                        .background(Circle().fill(.black.opacity(0.22)))
                }
                .padding(6)
            }

            // 文本只在底部
            HStack(spacing: 6) {
                SiteIcon(glyph: String(tab.displayTitle.prefix(1)), color: tab.tint, size: 16, corner: 4)
                Text(tab.isHome ? "新标签页" : tab.displayTitle)
                    .font(.system(size: 12)).foregroundStyle(Theme.Colors.primaryText).lineLimit(1)
                Spacer(minLength: 0)
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
