import SwiftUI

/// 设置中心：iOS 列表式结构，分组留白，右侧箭头进二级页。
struct SettingsView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        List {
            Section("基础") {
                nav("通用设置", "gearshape", Color(hex: 0x8E8E93)) { GeneralSettingsView() }
                nav("主页设置", "house", Color(hex: 0xFF9500)) { PlaceholderSettings(title: "主页设置") }
                nav("自定义设置", "slider.horizontal.3", Color(hex: 0x5856D6)) { CustomSettingsView() }
                nav("搜索引擎", "magnifyingglass", Color(hex: 0x0A84FF)) { SearchEngineView() }
                nav("标签页", "square.on.square", Color(hex: 0x34C759)) { PlaceholderSettings(title: "标签页") }
                nav("长按快捷操作", "hand.tap", Color(hex: 0xFF2D55)) { LongPressActionsView() }
            }

            Section("浏览") {
                nav("阅读模式", "doc.text", Color(hex: 0xAF52DE)) { PlaceholderSettings(title: "阅读模式") }
                nav("夜间模式", "moon", Color(hex: 0x5856D6)) { NightModeView() }
                nav("无图模式", "photo.on.rectangle.angled", Color(hex: 0x34C759)) { NoImageView() }
                toggleRow("网页下拉刷新", "arrow.clockwise", Color(hex: 0x0A84FF), .constant(true))
                toggleRow("全屏模式", "arrow.up.left.and.arrow.down.right", Color(hex: 0xFF9500), .constant(false))
                nav("浏览器标识 UA", "person.crop.circle", Color(hex: 0x8E8E93)) { PlaceholderSettings(title: "User-Agent") }
            }

            Section("功能") {
                nav("广告拦截", "shield.lefthalf.filled", Theme.Colors.safe) { AdBlockView() }
                nav("网页翻译", "character.bubble", Color(hex: 0x0A84FF)) { TranslateView() }
                nav("视频播放", "play.rectangle", Color(hex: 0xFF375F)) { PlaceholderSettings(title: "视频播放") }
                nav("文件管理", "folder", Color(hex: 0x5AC8FA)) { PlaceholderSettings(title: "文件管理") }
                nav("电子书阅读器", "book", Color(hex: 0xFF9500)) { EbookLibraryView() }
                nav("JavaScript 扩展", "curlybraces", Color(hex: 0x5856D6)) { JSExtensionsView() }
                nav("二维码工具", "qrcode", Color(hex: 0x000000)) { QRScannerView() }
                nav("手势按钮", "hand.draw", Color(hex: 0xFF2D55)) { GestureSettingsView() }
                nav("开发者工具", "hammer", Color(hex: 0x8E8E93)) { DevToolsView() }
            }

            Section("隐私与安全") {
                toggleRow("无痕浏览", "eyeglasses", Theme.Colors.incognito, $vm.isIncognito)
                toggleRow("Face ID 验证", "faceid", Color(hex: 0x34C759), .constant(false))
                nav("清除浏览数据", "trash", Theme.Colors.danger) { ClearDataView() }
                toggleRow("阻止跳转 App Store", "app.badge", Color(hex: 0xFF9500), .constant(true))
                nav("Cookie 管理", "circle.grid.cross", Color(hex: 0x5AC8FA)) { CookieManagerView() }
            }

            Section("同步与数据") {
                toggleRow("iCloud 同步", "icloud", Color(hex: 0x0A84FF), .constant(true))
                nav("导入书签", "square.and.arrow.down", Color(hex: 0x34C759)) { PlaceholderSettings(title: "导入书签") }
                nav("导出书签", "square.and.arrow.up", Color(hex: 0x34C759)) { PlaceholderSettings(title: "导出书签") }
                toggleRow("Handoff", "rectangle.2.swap", Color(hex: 0x5856D6), .constant(true))
            }

            Section("外观") {
                nav("主题", "paintbrush", Color(hex: 0xAF52DE)) { AppearanceSettingsView() }
                toggleRow("OLED 纯黑", "moonphase.new.moon", Color(hex: 0x000000), $vm.oledBlack)
                nav("沉浸式壁纸", "photo.artframe", Color(hex: 0x34C759)) { WallpaperSettingsView() }
                toggleRow("底部上滑打开主页", "arrow.up.to.line", Color(hex: 0x0A84FF), .constant(true))
            }

            Section("高级") {
                nav("设为默认浏览器", "checkmark.seal", Color(hex: 0x0A84FF)) { PlaceholderSettings(title: "默认浏览器") }
                nav("发送网站到主屏幕", "plus.app", Color(hex: 0xFF9500)) { PlaceholderSettings(title: "添加到主屏幕") }
                nav("Scheme 调用说明", "link", Color(hex: 0x8E8E93)) { SchemeHelpView() }
            }

            Section("关于") {
                nav("关于浏览器", "info.circle", Color(hex: 0x0A84FF)) { AboutView() }
                HStack {
                    Label { Text("版本号") } icon: { Image(systemName: "number").foregroundStyle(Theme.Colors.secondaryText) }
                    Spacer()
                    Text("1.0 (1)").foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, prompt: "搜索设置")
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } } }
    }

    // 复用：导航行
    private func nav<D: View>(_ title: String, _ symbol: String, _ color: Color, @ViewBuilder dest: () -> D) -> some View {
        NavigationLink { dest() } label: { SettingRowLabel(title: title, symbol: symbol, color: color) }
    }

    // 复用：开关行
    private func toggleRow(_ title: String, _ symbol: String, _ color: Color, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) { SettingRowLabel(title: title, symbol: symbol, color: color) }
    }
}

/// 设置行图标标签（彩色圆角小图标 + 标题）
struct SettingRowLabel: View {
    var title: String
    var symbol: String
    var color: Color
    var body: some View {
        Label {
            Text(title).foregroundStyle(Theme.Colors.primaryText)
        } icon: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                }
        }
    }
}
