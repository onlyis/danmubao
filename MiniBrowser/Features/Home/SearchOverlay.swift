import SwiftUI

/// 搜索输入态：键盘弹起、输入框聚焦、显示搜索建议/历史/剪贴板提示。
struct SearchOverlay: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @FocusState private var focused: Bool

    private let suggestions = ["天行九歌", "github trending", "swiftui 教程", "天气预报"]

    var body: some View {
        VStack(spacing: 0) {
            // 输入栏
            HStack(spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Colors.secondaryText)
                    TextField("搜索或输入网址", text: $text)
                        .focused($focused)
                        .font(.system(size: 16))
                        .submitLabel(.go)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit(go)
                    if !text.isEmpty {
                        Button { text = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.Colors.tertiaryText)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.m)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(Theme.Colors.groupedBackground)
                )

                Button("取消") { dismiss() }
                    .font(.system(size: 16))
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)

            Hairline()

            List {
                // 剪贴板提示：仅用 hasURLs 探测（不触发系统粘贴提示），点击时才读取
                if hasClipURL {
                    Section {
                        Button {
                            if let u = UIPasteboard.general.url?.absoluteString ?? UIPasteboard.general.string {
                                vm.open(url: u); dismiss()
                            }
                        } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                Image(systemName: "doc.on.clipboard").foregroundStyle(Theme.Colors.accent)
                                Text("打开剪贴板中的网址").font(.system(size: 15)).foregroundStyle(Theme.Colors.primaryText)
                            }
                        }
                    }
                }

                Section("搜索建议") {
                    ForEach(displayedSuggestions, id: \.self) { s in
                        Button { text = s; go() } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.Colors.tertiaryText)
                                Text(s).font(.system(size: 15))
                                    .foregroundStyle(Theme.Colors.primaryText)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.Colors.tertiaryText)
                                    .onTapGesture { text = s }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { focused = true } }
    }

    /// 仅探测剪贴板是否含网址（不触发系统粘贴提示），真正读取放到用户点击时。
    private var hasClipURL: Bool { UIPasteboard.general.hasURLs }

    private var displayedSuggestions: [String] {
        text.isEmpty ? suggestions : suggestions.filter { $0.localizedCaseInsensitiveContains(text) } + [text]
    }

    private func go() {
        guard !text.isEmpty else { return }
        vm.open(url: text, title: text)
        dismiss()
    }
}
