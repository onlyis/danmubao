import SwiftUI

/// 底部主菜单：顶部网页快捷操作行 + 可左右滑动分页的功能宫格 + 底部状态行。
struct MainMenuSheet: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private let columns = Array(repeating: GridItem(.flexible()), count: 4)

    var body: some View {
        VStack(spacing: 0) {
            quickActionRow
            Hairline().padding(.horizontal, Theme.Spacing.l)

            TabView(selection: $page) {
                menuGrid(MenuCatalog.page1).tag(0)
                menuGrid(MenuCatalog.page2).tag(1)
                menuGrid(MenuCatalog.page3).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(minHeight: 300)

            statusBar
        }
        .padding(.top, Theme.Spacing.s)
        .background((vm.isIncognito ? Color(hex: 0x111114) : Theme.Colors.card).ignoresSafeArea())
    }

    // 顶部网页快捷操作
    private var quickActionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xl) {
                QuickOp(symbol: "arrow.clockwise", title: "刷新") { vm.engine?.reload(); dismiss() }
                QuickOp(symbol: "doc.on.doc", title: "复制链接") {
                    UIPasteboard.general.string = vm.currentURL
                    dismiss(); vm.showToast("已复制链接", symbol: "doc.on.doc")
                }
                QuickOp(symbol: "square.and.arrow.up", title: "分享") { dismiss() }
                QuickOp(symbol: "bookmark", title: "加书签") {
                    vm.addBookmark(title: vm.currentTitle, url: vm.currentURL); dismiss()
                }
                QuickOp(symbol: "plus.app", title: "加到主页") { dismiss() }
                QuickOp(symbol: "xmark.square", title: "关闭标签") { dismiss() }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
        }
    }

    private func menuGrid(_ items: [MenuAction]) -> some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.xl) {
            ForEach(items) { item in
                MenuCell(item: item, isOn: toggleState(item)) {
                    handle(item)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.l)
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.s)
    }

    private var statusText: String {
        if vm.isIncognito { return "当前为无痕模式" }
        if vm.isNightMode { return "当前为夜间模式" }
        if vm.isAdBlockOn { return "已开启广告拦截" }
        return "当前为普通模式"
    }
    private var statusColor: Color {
        if vm.isIncognito { return Theme.Colors.incognito }
        if vm.isNightMode { return Color(hex: 0x5856D6) }
        return Theme.Colors.safe
    }

    private func toggleState(_ item: MenuAction) -> Bool {
        switch item.title {
        case "无痕模式": return vm.isIncognito
        case "夜间模式": return vm.isNightMode
        case "无图模式": return vm.isNoImageMode
        case "广告拦截": return vm.isAdBlockOn
        case "电脑版": return vm.isDesktopMode
        default: return false
        }
    }

    private func handle(_ item: MenuAction) {
        Haptics.light()
        switch item.title {
        case "设置": vm.route = .settings; dismiss()
        case "书签": vm.route = .bookmarks; dismiss()
        case "历史": vm.route = .history; dismiss()
        case "下载": vm.route = .downloads; dismiss()
        case "文件": vm.route = .files; dismiss()
        case "阅读模式": vm.route = .reading; dismiss()
        case "看图模式", "查看图片": vm.openImageMode(); dismiss()
        case "漫画模式": vm.route = .comic; dismiss()
        case "网页翻译": vm.route = .translate; dismiss()
        case "工具箱": vm.route = .toolbox; dismiss()
        case "开发者工具": vm.route = .devtools; dismiss()
        case "Cookie管理": vm.route = .cookies; dismiss()
        case "二维码": vm.route = .qrScanner; dismiss()
        case "JavaScript扩展": vm.route = .jsExtensions; dismiss()
        case "电子书": vm.route = .reader; dismiss()
        case "下载资源", "下载当前资源": vm.showDownloadConfirm = true; dismiss()
        case "视频悬浮": vm.showVideoFloat = true; dismiss()
        case "无痕模式": vm.toggleIncognito()
        case "夜间模式": withAnimation { vm.isNightMode.toggle() }
        case "无图模式": vm.isNoImageMode.toggle()
        case "广告拦截": vm.toggleAdBlock()
        case "标记广告": vm.showMarkAds = true; dismiss()
        case "电脑版": vm.isDesktopMode.toggle()
        case "网站设置": vm.showWebsiteSettings = true; dismiss()
        case "主页": vm.goHome(); dismiss()
        default: dismiss()
        }
    }
}

private struct QuickOp: View {
    var symbol: String, title: String, action: () -> Void
    var body: some View {
        Button(action: { Haptics.light(); action() }) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.Colors.accent.opacity(0.1)))
                Text(title).font(.system(size: 11)).foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .buttonStyle(PressableStyle())
    }
}

private struct MenuCell: View {
    let item: MenuAction
    var isOn: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: item.symbol)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(isOn ? .white : Theme.Colors.primaryText)
                    .frame(width: 50, height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isOn ? Theme.Colors.accent : Theme.Colors.groupedBackground)
                    )
                Text(item.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button { } label: { Label("设为长按快捷操作", systemImage: "hand.tap") }
            Button { } label: { Label("编辑菜单顺序", systemImage: "arrow.up.arrow.down") }
        }
    }
}

/// 菜单功能目录（分三屏）
enum MenuCatalog {
    static let page1: [MenuAction] = [
        .init(title: "设置", symbol: "gearshape"),
        .init(title: "书签", symbol: "bookmark"),
        .init(title: "历史", symbol: "clock.arrow.circlepath"),
        .init(title: "下载", symbol: "arrow.down.circle"),
        .init(title: "文件", symbol: "folder"),
        .init(title: "无痕模式", symbol: "eyeglasses", isToggle: true),
        .init(title: "夜间模式", symbol: "moon", isToggle: true),
        .init(title: "无图模式", symbol: "photo.on.rectangle.angled", isToggle: true),
        .init(title: "阅读模式", symbol: "doc.text"),
        .init(title: "看图模式", symbol: "photo.stack"),
        .init(title: "网页翻译", symbol: "character.bubble"),
        .init(title: "页面搜索", symbol: "doc.text.magnifyingglass"),
        .init(title: "分享", symbol: "square.and.arrow.up"),
        .init(title: "二维码", symbol: "qrcode"),
        .init(title: "自动刷新", symbol: "arrow.triangle.2.circlepath"),
        .init(title: "全屏模式", symbol: "arrow.up.left.and.arrow.down.right"),
        .init(title: "电脑版", symbol: "desktopcomputer", isToggle: true),
        .init(title: "标记广告", symbol: "hand.point.up.braille", isToggle: true),
        .init(title: "复制网址", symbol: "doc.on.doc"),
        .init(title: "主页", symbol: "house"),
    ]

    static let page2: [MenuAction] = [
        .init(title: "工具箱", symbol: "wrench.and.screwdriver"),
        .init(title: "开发者工具", symbol: "hammer"),
        .init(title: "查看源码", symbol: "chevron.left.forwardslash.chevron.right"),
        .init(title: "Eruda", symbol: "ladybug"),
        .init(title: "vConsole", symbol: "terminal"),
        .init(title: "Cookie管理", symbol: "circle.grid.cross"),
        .init(title: "网页长截图", symbol: "rectangle.portrait.and.arrow.right"),
        .init(title: "保存PDF", symbol: "doc.richtext"),
        .init(title: "保存HTML", symbol: "doc.plaintext"),
        .init(title: "WebArchive", symbol: "archivebox"),
        .init(title: "打印", symbol: "printer"),
        .init(title: "站内搜索", symbol: "magnifyingglass.circle"),
        .init(title: "扫码", symbol: "qrcode.viewfinder"),
        .init(title: "识别图中码", symbol: "viewfinder.circle"),
        .init(title: "生成二维码", symbol: "qrcode"),
        .init(title: "搜索引擎", symbol: "magnifyingglass"),
        .init(title: "JavaScript扩展", symbol: "curlybraces"),
        .init(title: "网站设置", symbol: "slider.horizontal.3"),
        .init(title: "站点证书", symbol: "lock.shield"),
        .init(title: "拦截跳转", symbol: "app.badge"),
    ]

    static let page3: [MenuAction] = [
        .init(title: "视频悬浮", symbol: "pip"),
        .init(title: "后台播放", symbol: "play.circle"),
        .init(title: "画中画", symbol: "pip.enter"),
        .init(title: "AirPlay", symbol: "airplayvideo"),
        .init(title: "DLNA投屏", symbol: "tv"),
        .init(title: "倍速播放", symbol: "gauge.with.dots.needle.67percent"),
        .init(title: "单曲循环", symbol: "repeat.1"),
        .init(title: "镜像播放", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right"),
        .init(title: "视频截图", symbol: "camera"),
        .init(title: "超级解码", symbol: "cpu"),
        .init(title: "下载资源", symbol: "arrow.down.to.line"),
        .init(title: "查看图片", symbol: "photo"),
        .init(title: "批量保存图", symbol: "square.and.arrow.down.on.square"),
        .init(title: "图片压缩", symbol: "rectangle.compress.vertical"),
        .init(title: "漫画模式", symbol: "books.vertical"),
        .init(title: "电子书", symbol: "book"),
        .init(title: "导入书签", symbol: "square.and.arrow.down"),
        .init(title: "导出书签", symbol: "square.and.arrow.up.on.square"),
        .init(title: "iCloud同步", symbol: "icloud"),
        .init(title: "Face ID锁", symbol: "faceid"),
    ]
}
