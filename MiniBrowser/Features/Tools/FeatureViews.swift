import SwiftUI

// MARK: - JavaScript 扩展（真实注入，见 UserScriptStore）
struct JSExtensionsView: View {
    @EnvironmentObject var store: UserScriptStore
    var body: some View {
        List {
            Section {
                ForEach($store.scripts) { $s in
                    NavigationLink {
                        ScriptEditView(script: $s, onDelete: { store.remove(s) })
                    } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            Image(systemName: "curlybraces").foregroundStyle(Theme.Colors.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name.isEmpty ? "未命名脚本" : s.name).font(.system(size: 15)).foregroundStyle(Theme.Colors.primaryText)
                                Text(s.match).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.Colors.secondaryText).lineLimit(1)
                            }
                            Spacer()
                            Toggle("", isOn: $s.enabled).labelsHidden()
                        }
                    }
                }
            } footer: {
                Text("在匹配的网站上自动注入运行自定义 JavaScript。新建/修改在下次打开匹配网页的新标签时生效。")
            }
        }
        .navigationTitle("JavaScript 扩展").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.add(UserScript(name: "", match: "*://*/*",
                                         code: "// 在此编写脚本\n(function(){\n  console.log('hello');\n})();"))
                } label: { Image(systemName: "plus") }
            }
        }
    }
}

struct ScriptEditView: View {
    @Binding var script: UserScript
    var onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("基本") {
                TextField("脚本名称", text: $script.name)
                TextField("匹配网址（如 *://*.example.com/*）", text: $script.match)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .font(.system(size: 14, design: .monospaced))
            }
            Section("运行时机") {
                Picker("时机", selection: $script.atDocumentEnd) {
                    Text("页面开始").tag(false); Text("页面结束").tag(true)
                }.pickerStyle(.segmented)
            }
            Section("脚本内容") {
                TextEditor(text: $script.code)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 200)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            Section {
                Toggle("启用", isOn: $script.enabled)
            }
            Section {
                Button("删除脚本", role: .destructive) { onDelete(); dismiss() }
            }
        }
        .navigationTitle(script.name.isEmpty ? "新建脚本" : script.name).navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 网页源码查看
struct SourceCodeView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    let code: String

    var body: some View {
        NavigationStack {
            ScrollView([.vertical, .horizontal]) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.Colors.primaryText)
                    .textSelection(.enabled)
                    .padding(Theme.Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.Colors.groupedBackground.ignoresSafeArea())
            .navigationTitle("网页源码").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = code
                        vm.showToast("已复制源码", symbol: "doc.on.doc")
                    } label: { Image(systemName: "doc.on.doc") }
                }
            }
        }
    }
}

// MARK: - 开发者工具
struct DevToolsView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    private let tools: [(String, String, Color)] = [
        ("查看源码", "chevron.left.forwardslash.chevron.right", Color(hex: 0x5856D6)),
        ("Eruda 控制台", "ladybug", Color(hex: 0xFF3B30)),
        ("vConsole", "terminal", Color(hex: 0x34C759)),
        ("Cookie 管理", "circle.grid.cross", Color(hex: 0x5AC8FA)),
        ("网络请求", "antenna.radiowaves.left.and.right", Color(hex: 0xFF9500)),
        ("DOM 检查", "rectangle.dashed", Color(hex: 0xAF52DE)),
    ]
    var body: some View {
        List {
            ForEach(tools, id: \.0) { t in
                Button { handle(t.0) } label: { SettingRowLabel(title: t.0, symbol: t.1, color: t.2) }
            }
        }
        .navigationTitle("开发者工具").navigationBarTitleDisplayMode(.inline)
        .toolbar { dismissDoneIfRoot() }
    }

    /// 已接真的开发者工具入口；注入控制台后收起本页，让网页右下角的调试浮窗可见。
    private func handle(_ title: String) {
        switch title {
        case "查看源码":
            vm.viewSource()
            dismiss()
        case "Eruda 控制台":
            if vm.performMenuAction("Eruda") { dismiss() }
        case "vConsole":
            if vm.performMenuAction("vConsole") { dismiss() }
        default:
            break   // Cookie 管理 / 网络请求 / DOM 检查 仍为占位
        }
    }
}

// MARK: - Cookie 管理

// MARK: - 网页翻译
struct TranslateView: View {
    @State private var target = "中文"
    @State private var alwaysThis = false
    private let langs = ["中文", "英文", "日文", "韩文", "法文", "德文", "西班牙文",
                         "葡萄牙文", "俄文", "阿拉伯文", "土耳其文", "泰文", "越南文"]
    var body: some View {
        List {
            Section {
                LabeledContent("源语言", value: "自动检测")
                Picker("目标语言", selection: $target) {
                    ForEach(langs, id: \.self) { Text($0) }
                }
            }
            Section {
                Button { } label: { Label("翻译当前页面", systemImage: "character.bubble") }
                Button { } label: { Label("翻译选中文字", systemImage: "text.cursor") }
                Button { } label: { Label("恢复原文", systemImage: "arrow.uturn.backward") }
            }
            Section {
                Toggle("总是翻译此语言", isOn: $alwaysThis)
                Button("此网站不再翻译") { }.foregroundStyle(Theme.Colors.danger)
            }
        }
        .navigationTitle("网页翻译").navigationBarTitleDisplayMode(.inline)
        .toolbar { dismissDoneIfRoot() }
    }
}

/// 若作为全屏路由根，提供「完成」按钮
struct dismissDoneIfRoot: ToolbarContent {
    @Environment(\.dismiss) private var dismiss
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
    }
}
