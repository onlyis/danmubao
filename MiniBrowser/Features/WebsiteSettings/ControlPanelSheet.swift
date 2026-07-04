import SwiftUI

/// 盾牌控制面板：点击地址栏左侧盾牌打开。聚焦「当前网页」的快捷操作，
/// 可长按编辑（删除/拖动/添加），与主菜单复用 `EditableActionGrid`。底部可进入完整网站设置。
struct ControlPanelSheet: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false

    private var host: String { vm.currentURL.isEmpty ? "未打开网页" : vm.currentURL }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline().padding(.horizontal, Theme.Spacing.l)

            ScrollView {
                EditableActionGrid(
                    titles: $vm.panelItems,
                    pool: ControlPanelCatalog.all,
                    isOn: { vm.actionIsOn($0) },
                    perform: { if vm.performMenuAction($0) { dismiss() } },
                    editing: $editing
                )
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.l)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: .infinity)

            Hairline().padding(.horizontal, Theme.Spacing.l)
            Button {
                dismiss()
                // 先关本面板，稍后再呈现详细设置，避免 sheet 叠 sheet 呈现失败
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { vm.showWebsiteSettings = true }
            } label: {
                HStack {
                    Label("更多网站设置", systemImage: "slider.horizontal.3")
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(Theme.Colors.tertiaryText)
                }
                .font(.system(size: 15))
                .foregroundStyle(Theme.Colors.primaryText)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.m)
            }
        }
        .padding(.top, Theme.Spacing.s)
        .background((vm.isIncognito ? Color(hex: 0x111114) : Theme.Colors.card).ignoresSafeArea())
        .presentationDetents([.height(440), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Theme.Radius.sheet)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            SiteIcon(glyph: String(host.prefix(1)).uppercased(), color: Theme.Colors.accent, size: 34, corner: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(host).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Colors.primaryText).lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.Colors.safe)
                    Text("控制面板").font(.system(size: 11)).foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.15)) { editing.toggle() }
            } label: {
                Text(editing ? "完成" : "编辑")
                    .font(.system(size: 15, weight: editing ? .semibold : .regular))
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.m)
    }
}

/// 控制面板功能目录：以「当前网页操作」为主。作为可添加功能的池。
enum ControlPanelCatalog {
    static let all: [MenuAction] = [
        .init(title: "刷新", symbol: "arrow.clockwise"),
        .init(title: "后退", symbol: "chevron.left"),
        .init(title: "前进", symbol: "chevron.right"),
        .init(title: "加入书签", symbol: "bookmark"),
        .init(title: "复制网址", symbol: "doc.on.doc"),
        .init(title: "分享", symbol: "square.and.arrow.up"),
        .init(title: "页面查找", symbol: "doc.text.magnifyingglass"),
        .init(title: "看图模式", symbol: "photo.stack"),
        .init(title: "网页翻译", symbol: "character.bubble"),
        .init(title: "视频悬浮", symbol: "pip"),
        .init(title: "保存PDF", symbol: "doc.richtext"),
        .init(title: "保存HTML", symbol: "doc.plaintext"),
        .init(title: "查看源码", symbol: "chevron.left.forwardslash.chevron.right"),
        .init(title: "打印", symbol: "printer"),
        .init(title: "下载资源", symbol: "arrow.down.to.line"),
        .init(title: "标记广告", symbol: "hand.point.up.braille"),
        .init(title: "滚动到顶", symbol: "arrow.up.to.line"),
        .init(title: "滚动到底", symbol: "arrow.down.to.line"),
        .init(title: "二维码", symbol: "qrcode"),
        .init(title: "夜间模式", symbol: "moon", isToggle: true),
        .init(title: "电脑版", symbol: "desktopcomputer", isToggle: true),
        .init(title: "无图模式", symbol: "photo.on.rectangle.angled", isToggle: true),
        .init(title: "广告拦截", symbol: "shield.lefthalf.filled", isToggle: true),
    ]
    /// 默认展示的快捷功能（首次 / 未自定义时）。
    static let defaultTitles: [String] = [
        "刷新", "加入书签", "复制网址", "分享", "页面查找", "看图模式", "网页翻译",
        "保存PDF", "查看源码", "滚动到顶", "滚动到底",
        "夜间模式", "电脑版", "无图模式", "广告拦截",
    ]
}

/// 系统分享面板（UIActivityViewController）。
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
