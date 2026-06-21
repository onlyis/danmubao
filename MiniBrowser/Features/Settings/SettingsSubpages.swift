import SwiftUI

// MARK: - 通用设置
struct GeneralSettingsView: View {
    @State private var openLast = true
    @State private var pullRefresh = true
    @State private var pullSearch = true
    @State private var anySwipeBack = false
    @State private var tapPaging = false
    @State private var quickOpenClip = true
    @State private var blockAppStore = true
    @State private var speed = 1

    var body: some View {
        List {
            Section {
                Toggle("启动时打开上次网页", isOn: $openLast)
                Toggle("网页下拉刷新", isOn: $pullRefresh)
                Toggle("主页下拉搜索", isOn: $pullSearch)
                Toggle("任意位置滑动返回", isOn: $anySwipeBack)
                Toggle("屏幕点击翻页", isOn: $tapPaging)
            }
            Section {
                Toggle("快速打开复制网址", isOn: $quickOpenClip)
                Toggle("阻止跳转 App Store", isOn: $blockAppStore)
            }
            Section("页面滑动速度") {
                Picker("速度", selection: $speed) {
                    Text("慢").tag(0); Text("标准").tag(1); Text("快").tag(2)
                }.pickerStyle(.segmented)
            }
            Section {
                NavigationLink("长按快捷操作") { LongPressActionsView() }
                NavigationLink("设置为默认浏览器") { PlaceholderSettings(title: "默认浏览器") }
                NavigationLink("发送网站到系统主屏幕") { PlaceholderSettings(title: "添加到主屏幕") }
            }
        }
        .navigationTitle("通用设置").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 自定义设置
struct CustomSettingsView: View {
    @State private var showTabBar = false
    @State private var swipeUpHome = true
    @State private var hideSearch = false
    @State private var hideSites = false
    @State private var oled = false
    @State private var perRow = 4

    var body: some View {
        List {
            Section("布局") {
                Toggle("显示标签导航栏", isOn: $showTabBar)
                Toggle("底部工具栏上滑打开主页", isOn: $swipeUpHome)
                Toggle("隐藏主页搜索框", isOn: $hideSearch)
                Toggle("隐藏常用网站", isOn: $hideSites)
                Stepper("图标每行数量：\(perRow)", value: $perRow, in: 3...5)
            }
            Section("自定义") {
                NavigationLink("自定义底部工具栏按钮") { ToolbarCustomizeView() }
                NavigationLink("自定义菜单按钮顺序") { PlaceholderSettings(title: "菜单顺序") }
                NavigationLink("自定义首页壁纸") { PlaceholderSettings(title: "首页壁纸") }
                NavigationLink("自定义站点图标") { PlaceholderSettings(title: "站点图标") }
                NavigationLink("自定义字体", destination: PlaceholderSettings(title: "字体"))
            }
            Section("夜间外观") {
                Toggle("OLED 纯黑", isOn: $oled)
                NavigationLink("网页护眼色") { PlaceholderSettings(title: "护眼色") }
            }
        }
        .navigationTitle("自定义设置").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 自定义底部工具栏按钮（任意功能、1…8 个）
struct ToolbarCustomizeView: View {
    @EnvironmentObject var vm: BrowserViewModel
    private var available: [ToolbarItemKind] { ToolbarItemKind.allCases.filter { !vm.toolbarItems.contains($0) } }

    var body: some View {
        List {
            Section {
                ForEach(vm.toolbarItems) { item in
                    row(item)
                        .deleteDisabled(vm.toolbarItems.count <= 1)
                }
                .onMove { vm.moveToolbarItems(from: $0, to: $1) }
                .onDelete { idx in idx.map { vm.toolbarItems[$0] }.forEach(vm.removeToolbarItem) }
            } header: {
                Text("当前工具栏（\(vm.toolbarItems.count)/8）· 编辑可排序，左滑删除")
            } footer: {
                Text("最少 1 个、最多 8 个。「手势按钮」是特色项，样式可在「手势按钮 → 工具栏图标醒目显示」里切换。")
            }

            if !available.isEmpty {
                Section("可添加功能") {
                    ForEach(available) { item in
                        Button { vm.addToolbarItem(item) } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                iconLabel(item)
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(vm.toolbarItems.count >= 8 ? Theme.Colors.tertiaryText : Theme.Colors.accent)
                            }
                        }
                        .disabled(vm.toolbarItems.count >= 8)
                    }
                }
            }
        }
        .navigationTitle("工具栏按钮").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
    }

    private func row(_ item: ToolbarItemKind) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            iconLabel(item)
            if item.isGesture {
                Text("特色").font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Theme.Colors.accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.Colors.accent)
            }
            Spacer()
        }
    }
    private func iconLabel(_ item: ToolbarItemKind) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: item.symbol)
                .font(.system(size: 17))
                .foregroundStyle(item.isGesture ? Theme.Colors.accent : Theme.Colors.primaryText)
                .frame(width: 26)
            Text(item.title).foregroundStyle(item.isGesture ? Theme.Colors.accent : Theme.Colors.primaryText)
        }
    }
}

// MARK: - 搜索引擎（真实：选择即生效并持久化，见 BrowserViewModel.searchEngine）
struct SearchEngineView: View {
    @EnvironmentObject var vm: BrowserViewModel

    var body: some View {
        List {
            Section("默认搜索引擎") {
                ForEach(vm.allSearchEngines) { e in
                    Button { Haptics.light(); vm.searchEngine = e } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            SiteIconSmall(glyph: e.glyph, color: e.color)
                            Text(e.name).foregroundStyle(Theme.Colors.primaryText)
                            Spacer()
                            if e.id == vm.searchEngine.id {
                                Image(systemName: "checkmark").foregroundStyle(Theme.Colors.accent)
                            }
                        }
                    }
                    .swipeActions {
                        // 仅自定义引擎可删除
                        if vm.customEngines.contains(where: { $0.id == e.id }) {
                            Button(role: .destructive) { vm.removeCustomEngine(e) } label: { Label("删除", systemImage: "trash") }
                        }
                    }
                }
            }
            Section {
                NavigationLink("自定义搜索引擎") { CustomEngineEditView() }
            } footer: {
                Text("当前：\(vm.searchEngine.name)　\(vm.searchEngine.template)")
                    .font(.system(size: 12, design: .monospaced))
            }
        }
        .navigationTitle("搜索引擎").navigationBarTitleDisplayMode(.inline)
        .toolbar { dismissDoneIfRoot() }
    }
}

struct CustomEngineEditView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        url.contains(".") && (url.contains("%s") || url.contains("="))
    }

    var body: some View {
        Form {
            Section("名称") { TextField("搜索引擎名称", text: $name) }
            Section("搜索 URL") {
                TextField("https://example.com/?q=%s", text: $url)
                    .autocorrectionDisabled().textInputAutocapitalization(.never).keyboardType(.URL)
                Text("用 %s 作为关键词占位符；或以 ?q= 等结尾，关键词会追加到末尾。")
                    .font(.system(size: 12)).foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .navigationTitle("添加搜索引擎").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { vm.addCustomEngine(name: name, template: url); dismiss() }
                    .fontWeight(.semibold).disabled(!canSave)
            }
        }
    }
}

// MARK: - 长按快捷操作
struct LongPressActionsView: View {
    private let buttons = ["菜单按钮", "后退按钮", "前进按钮", "主页按钮", "标签按钮", "刷新按钮"]
    @State private var mapping: [String: String] = ["菜单按钮": "打开设置", "主页按钮": "新建标签页"]

    var body: some View {
        List {
            Section {
                ForEach(buttons, id: \.self) { b in
                    NavigationLink {
                        ShortcutPickerView(button: b, mapping: $mapping)
                    } label: {
                        HStack {
                            Text(b).foregroundStyle(Theme.Colors.primaryText)
                            Spacer()
                            Text(mapping[b] ?? "未设置")
                                .font(.system(size: 14)).foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                }
            } footer: {
                Text("为工具栏按钮设置长按后的快捷功能。")
            }
        }
        .navigationTitle("长按快捷操作").navigationBarTitleDisplayMode(.inline)
    }
}

struct ShortcutPickerView: View {
    let button: String
    @Binding var mapping: [String: String]
    @Environment(\.dismiss) private var dismiss
    private let options = ["打开设置", "打开书签", "打开历史", "打开下载", "打开文件", "切换夜间模式",
                           "切换无图模式", "进入阅读模式", "进入看图模式", "网页翻译", "页面搜索",
                           "标记广告", "网站设置", "新建标签页", "关闭当前标签页", "复制网址",
                           "分享网页", "二维码", "自动刷新", "全屏模式", "开发者工具", "打开图书馆"]
    var body: some View {
        List {
            ForEach(options, id: \.self) { opt in
                Button { mapping[button] = opt; dismiss() } label: {
                    HStack {
                        Text(opt).foregroundStyle(Theme.Colors.primaryText)
                        Spacer()
                        if mapping[button] == opt { Image(systemName: "checkmark").foregroundStyle(Theme.Colors.accent) }
                    }
                }
            }
        }
        .navigationTitle(button).navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 夜间模式
struct NightModeView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @State private var webDark = true
    @State private var dimImages = true
    var body: some View {
        List {
            Section("模式") {
                Picker("外观", selection: $vm.appearanceMode) {
                    ForEach(BrowserViewModel.AppearanceMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.inline).labelsHidden()
            }
            Section {
                Toggle("OLED 纯黑模式", isOn: $vm.oledBlack)
                Toggle("网页内容应用深色", isOn: $webDark)
                Toggle("降低图片亮度", isOn: $dimImages)
                Toggle("仅浏览器 UI 深色", isOn: .constant(false))
            }
            Section("网页护眼") {
                NavigationLink("网页护眼色", destination: PlaceholderSettings(title: "护眼色"))
                Toggle("自动定时开启", isOn: .constant(false))
            }
        }
        .navigationTitle("夜间模式").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 无图模式
struct NoImageView: View {
    @EnvironmentObject var vm: BrowserViewModel
    var body: some View {
        List {
            Section {
                Toggle("全局无图模式", isOn: Binding(get: { vm.isNoImageMode }, set: { _ in vm.toggleNoImage() }))
                Toggle("智能无图", isOn: .constant(false))
                Toggle("仅 Wi-Fi 加载图片", isOn: .constant(true))
            }
            Section {
                Toggle("显示图片占位符", isOn: .constant(true))
                Toggle("点击占位符加载单张", isOn: .constant(true))
            }
        }
        .navigationTitle("无图模式").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 清除数据
struct ClearDataView: View {
    @State private var showConfirm = false
    private let items = ["浏览历史", "Cookie 和网站数据", "缓存图片和文件", "搜索历史", "自动填充数据"]
    @State private var selected: Set<String> = ["浏览历史", "缓存图片和文件"]
    var body: some View {
        List {
            Section {
                ForEach(items, id: \.self) { item in
                    Button { toggle(item) } label: {
                        HStack {
                            Text(item).foregroundStyle(Theme.Colors.primaryText)
                            Spacer()
                            if selected.contains(item) { Image(systemName: "checkmark").foregroundStyle(Theme.Colors.accent) }
                        }
                    }
                }
            }
            Section {
                Button("清除所选数据") { showConfirm = true }.foregroundStyle(Theme.Colors.danger).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("清除浏览数据").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("确认清除所选数据？此操作不可撤销。", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("清除", role: .destructive) { }
            Button("取消", role: .cancel) { }
        }
    }
    private func toggle(_ s: String) { if selected.contains(s) { selected.remove(s) } else { selected.insert(s) } }
}

// MARK: - Scheme 说明
struct SchemeHelpView: View {
    private let schemes = [
        ("启动 App", "minibrowser://"),
        ("搜索或打开 URL", "minibrowser://open?url="),
        ("新建下载", "minibrowser://download?url="),
        ("扫描二维码", "minibrowser://scan"),
        ("开始搜索", "minibrowser://search?q="),
        ("打开图书馆", "minibrowser://library"),
        ("打开书签", "minibrowser://bookmarks"),
    ]
    var body: some View {
        List {
            Section { } footer: { Text("通过 URL Scheme 从其他 App 或快捷指令调用本浏览器。") }
            Section {
                ForEach(schemes, id: \.0) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.0).font(.system(size: 15)).foregroundStyle(Theme.Colors.primaryText)
                        Text(s.1).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.Colors.accent)
                    }.padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Scheme 调用").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 关于
struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    SiteIcon(glyph: "", color: Theme.Colors.accent, symbol: "safari.fill", size: 72, corner: 18)
                    Text("浏览器").font(.system(size: 20, weight: .bold))
                    Text("版本 1.0 (1)").font(.system(size: 13)).foregroundStyle(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .listRowBackground(Color.clear)
            }
            Section {
                NavigationLink("更新日志", destination: ChangelogView())
                NavigationLink("隐私政策", destination: PrivacyPolicyView())
                NavigationLink("用户协议", destination: UserAgreementView())
            }
            Section("联系我们") {
                LabeledContent("邮箱", value: "support@example.com")
                LabeledContent("微信", value: "minibrowser")
                Button("给我们评分") { }
                Button("反馈问题") { }
            }
        }
        .navigationTitle("关于").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 占位二级设置页（统一样式）
struct PlaceholderSettings: View {
    let title: String
    var body: some View {
        List {
            Section {
                Toggle("启用", isOn: .constant(true))
                LabeledContent("状态", value: "默认")
            } footer: {
                Text("「\(title)」详细选项。本阶段为 UI 占位，流程已串联。")
            }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
