import SwiftUI

/// 网站设置面板：点击地址栏左侧盾牌打开。针对当前域名单独设置。
struct WebsiteSettingsSheet: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var videoFloat = true
    @State private var clipboard = false
    @State private var newTabLinks = false
    @State private var readingEnhance = true
    @State private var ua = "默认"

    private var host: String { vm.currentURL.isEmpty ? "example.com" : vm.currentURL }

    var body: some View {
        NavigationStack {
            List {
                // 站点头部
                Section {
                    HStack(spacing: Theme.Spacing.m) {
                        SiteIcon(glyph: String(host.prefix(1)).uppercased(), color: Theme.Colors.accent, size: 44, corner: 10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(host).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Theme.Colors.safe)
                                Text("连接安全").font(.system(size: 12)).foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Toggle(isOn: $videoFloat) { rowLabel("视频悬浮", "pip") }
                    Toggle(isOn: $vm.isAdBlockOn) { rowLabel("广告拦截", "shield.lefthalf.filled") }
                    Toggle(isOn: $vm.isNoImageMode) { rowLabel("无图模式", "photo.on.rectangle.angled") }
                    Toggle(isOn: $clipboard) { rowLabel("允许访问剪贴板", "doc.on.clipboard") }
                    Toggle(isOn: $newTabLinks) { rowLabel("新标签页打开链接", "plus.square.on.square") }
                }

                Section {
                    Toggle(isOn: $readingEnhance) { rowLabel("阅读模式增强", "doc.text") }
                    Toggle(isOn: $vm.isNightMode) { rowLabel("网页夜间模式", "moon") }
                    Toggle(isOn: $vm.isDesktopMode) { rowLabel("桌面版网站", "desktopcomputer") }
                    Picker(selection: $ua) {
                        ForEach(["默认", "iPhone", "iPad", "Mac", "Windows", "自定义"], id: \.self) { Text($0) }
                    } label: { rowLabel("User-Agent", "person.crop.circle") }
                    NavigationLink { JSExtensionsView() } label: { rowLabel("JavaScript 脚本", "curlybraces") }
                }

                Section {
                    Button { } label: { rowLabel("清除本站广告规则", "trash", tint: Theme.Colors.danger) }
                    Button { } label: { rowLabel("清除本站 Cookie", "trash", tint: Theme.Colors.danger) }
                    Button { } label: { rowLabel("查看站点证书", "lock.shield", tint: Theme.Colors.accent) }
                    Button { } label: { rowLabel("站点权限重置", "arrow.counterclockwise", tint: Theme.Colors.accent) }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("网站设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("恢复默认") { }.font(.system(size: 15))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func rowLabel(_ title: String, _ symbol: String, tint: Color = Theme.Colors.primaryText) -> some View {
        Label {
            Text(title).foregroundStyle(tint == Theme.Colors.primaryText ? Theme.Colors.primaryText : tint)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint == Theme.Colors.primaryText ? Theme.Colors.accent : tint)
        }
    }
}
