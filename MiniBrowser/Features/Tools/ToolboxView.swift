import SwiftUI

/// 工具箱：开发者工具与网页保存/二维码等高级功能列表。
struct ToolboxView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("开发") {
                row("查看源码", "chevron.left.forwardslash.chevron.right", Color(hex: 0x5856D6)) { }
                navRow("开发者工具", "hammer", Color(hex: 0x8E8E93)) { DevToolsView() }
                row("Eruda", "ladybug", Color(hex: 0xFF3B30)) { }
                row("vConsole", "terminal", Color(hex: 0x34C759)) { }
                navRow("Cookie 管理", "circle.grid.cross", Color(hex: 0x5AC8FA)) { CookieManagerView() }
            }
            Section("保存网页") {
                row("网页长截图", "rectangle.portrait.and.arrow.right", Color(hex: 0xFF9500)) { }
                row("保存为 PDF", "doc.richtext", Color(hex: 0xFF3B30)) { }
                row("保存为 HTML", "doc.plaintext", Color(hex: 0x0A84FF)) { }
                row("保存为 WebArchive", "archivebox", Color(hex: 0xAF52DE)) { }
                row("打印", "printer", Color(hex: 0x8E8E93)) { }
            }
            Section("二维码") {
                navRow("扫描二维码", "qrcode.viewfinder", Color(hex: 0x000000)) { QRScannerView() }
                navRow("识别图片二维码", "viewfinder.circle", Color(hex: 0x34C759)) { QRScannerView() }
                navRow("生成链接二维码", "qrcode", Color(hex: 0x0A84FF)) { QRGenerateView() }
            }
            Section("其他") {
                row("页面搜索", "doc.text.magnifyingglass", Color(hex: 0xFF9500)) { }
                row("站内搜索", "magnifyingglass.circle", Color(hex: 0x0A84FF)) { }
                row("自动刷新", "arrow.triangle.2.circlepath", Color(hex: 0x34C759)) { }
                row("查看站点证书", "lock.shield", Color(hex: 0x34C759)) { }
                row("阻止跳转 App Store", "app.badge", Color(hex: 0xFF3B30)) { }
                row("打开复制的网址", "doc.on.clipboard", Color(hex: 0x5AC8FA)) { }
            }
        }
        .navigationTitle("工具箱").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } } }
    }

    private func row(_ t: String, _ s: String, _ c: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { SettingRowLabel(title: t, symbol: s, color: c) }
    }
    private func navRow<D: View>(_ t: String, _ s: String, _ c: Color, @ViewBuilder dest: () -> D) -> some View {
        NavigationLink { dest() } label: { SettingRowLabel(title: t, symbol: s, color: c) }
    }
}

/// 生成二维码
struct QRGenerateView: View {
    @EnvironmentObject var vm: BrowserViewModel
    private var content: String { vm.currentURL.isEmpty ? "https://example.com" : vm.currentURL }
    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            RoundedRectangle(cornerRadius: Theme.Radius.large)
                .fill(Color.white)
                .frame(width: 220, height: 220)
                .overlay {
                    if let img = QRCode.generate(content) {
                        Image(uiImage: img).interpolation(.none).resizable().scaledToFit().padding(18)
                    } else {
                        Image(systemName: "qrcode").resizable().scaledToFit().padding(24).foregroundStyle(.black)
                    }
                }
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            Text(content)
                .font(.system(size: 14)).foregroundStyle(Theme.Colors.secondaryText)
            HStack(spacing: Theme.Spacing.xl) {
                qrAction("保存图片", "square.and.arrow.down")
                qrAction("分享", "square.and.arrow.up")
                qrAction("复制内容", "doc.on.doc")
            }
            Spacer()
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("二维码").navigationBarTitleDisplayMode(.inline)
    }
    private func qrAction(_ t: String, _ s: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: s).font(.system(size: 20)).foregroundStyle(Theme.Colors.accent)
                .frame(width: 48, height: 48).background(Circle().fill(Theme.Colors.accent.opacity(0.1)))
            Text(t).font(.system(size: 11)).foregroundStyle(Theme.Colors.secondaryText)
        }
    }
}
