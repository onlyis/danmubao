import SwiftUI

/// 底部主菜单：顶部标题头 + 可编辑功能宫格（长按删除/拖动/添加）+ 底部状态行。
struct MainMenuSheet: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var page = 0

    /// 所有页已用标题的并集（用于「添加」时排除已存在的功能）。
    private var usedTitles: [String] { vm.menuItems.flatMap { $0 } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline().padding(.horizontal, Theme.Spacing.l)

            TabView(selection: $page) {
                ForEach(vm.menuItems.indices, id: \.self) { i in
                    ScrollView {
                        EditableActionGrid(
                            titles: pageBinding(i),
                            pool: MenuCatalog.all,
                            usedTitles: usedTitles,
                            isOn: { vm.actionIsOn($0) },
                            perform: { if vm.performMenuAction($0) { dismiss() } },
                            editing: $editing
                        )
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.top, Theme.Spacing.l)
                        .padding(.bottom, 36)
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(maxHeight: .infinity)

            if editing {
                Text("编辑的是当前页 · 长按拖动排序 · 点角标删除 · 翻页可改其它页")
                    .font(.system(size: 11)).foregroundStyle(Theme.Colors.tertiaryText)
                    .padding(.bottom, 4)
            }
            statusBar
        }
        .padding(.top, Theme.Spacing.s)
        .background((vm.isIncognito ? Color(hex: 0x111114) : Theme.Colors.card).ignoresSafeArea())
    }

    /// 手动构造对某一页的绑定（改某页 → 触发 vm.menuItems didSet 落盘）。
    private func pageBinding(_ i: Int) -> Binding<[String]> {
        Binding(get: { vm.menuItems[i] }, set: { vm.menuItems[i] = $0 })
    }

    // 顶部标题头（盾牌 + 当前页 + 编辑/设置）
    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 19))
                .foregroundStyle(vm.isAdBlockOn ? Theme.Colors.safe : Theme.Colors.secondaryText)
            Text(vm.isBrowsing ? (vm.currentTitle.isEmpty ? vm.currentURL : vm.currentTitle) : "主页")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.primaryText)
                .lineLimit(1)
            Spacer()
            if editing {
                Button { withAnimation(.easeOut(duration: 0.15)) { editing = false } } label: {
                    Text("完成").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Colors.accent)
                }
            } else {
                Button { withAnimation(.easeOut(duration: 0.15)) { editing = true } } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 18)).foregroundStyle(Theme.Colors.secondaryText)
                }
                Button { dismiss(); vm.route = .settings } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 20)).foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.m)
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

}

/// 菜单功能目录（分三屏，作为「可添加功能」的完整池）
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
        .init(title: "稍后读", symbol: "text.badge.plus"),
        .init(title: "阅读列表", symbol: "text.book.closed"),
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
        .init(title: "媒体嗅探", symbol: "antenna.radiowaves.left.and.right"),
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

    /// 去重后的完整目录（按页顺序），作为「添加功能」的池与标题→功能查表。
    static let all: [MenuAction] = {
        var seen = Set<String>(); var out: [MenuAction] = []
        for a in page1 + page2 + page3 where !seen.contains(a.title) { seen.insert(a.title); out.append(a) }
        return out
    }()
    /// 默认分页布局（首次启动 / 未自定义时）：三页，与原 60 项一致。
    static let defaultPages: [[String]] = [page1, page2, page3].map { $0.map(\.title) }
}
