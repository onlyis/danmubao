import SwiftUI

/// Wi-Fi 文件传输界面：开关启停局域网 HTTP 服务，显示访问 URL 与其二维码，
/// 电脑/手机在同一 Wi-Fi 下用浏览器打开即可上传文件到下载目录。
struct WiFiTransferView: View {
    @StateObject private var server = WiFiTransferServer()
    @Environment(\.dismiss) private var dismiss

    /// 开关绑定：开启时启动服务，关闭时停止。
    private var runningBinding: Binding<Bool> {
        Binding(
            get: { server.isRunning },
            set: { on in on ? server.start() : server.stop() }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: runningBinding) {
                        Label("启用 Wi-Fi 传输", systemImage: "wifi")
                    }
                    .tint(Theme.Colors.accent)
                } footer: {
                    Text("开启后，电脑或其它手机用浏览器访问下方地址即可上传文件；上传的文件将保存到「文件 → 下载目录」。")
                }

                switch server.status {
                case .starting:
                    Section {
                        HStack(spacing: Theme.Spacing.m) {
                            ProgressView()
                            Text("正在启动服务…").font(.system(size: 15)).foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                case let .running(url):
                    runningSection(url: url)
                case let .failed(message):
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 14)).foregroundStyle(Theme.Colors.danger)
                    }
                case .stopped:
                    Section {
                        Text("服务未开启").font(.system(size: 14)).foregroundStyle(Theme.Colors.tertiaryText)
                    }
                }

                Section("使用说明") {
                    instructionRow(1, "确保电脑/手机与本机在同一 Wi-Fi 网络")
                    instructionRow(2, "在电脑浏览器中打开上方地址（或扫描二维码）")
                    instructionRow(3, "选择文件上传，文件会出现在「下载目录」")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Wi-Fi 传输")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .onDisappear { server.stop() }
        }
    }

    /// 运行中：URL + 二维码 + 复制 + 已接收计数。
    @ViewBuilder
    private func runningSection(url: String) -> some View {
        Section("访问地址") {
            VStack(spacing: Theme.Spacing.l) {
                if let qr = QRCode.generate(url) {
                    Image(uiImage: qr)
                        .interpolation(.none).resizable().scaledToFit()
                        .frame(width: 200, height: 200)
                        .padding(Theme.Spacing.m)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Radius.medium))
                }
                Text(url)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Colors.accent)
                    .textSelection(.enabled)
                Text("同一 Wi-Fi 下用浏览器打开此地址")
                    .font(.system(size: 12)).foregroundStyle(Theme.Colors.secondaryText)
                Button {
                    UIPasteboard.general.string = url
                } label: {
                    Label("复制地址", systemImage: "doc.on.doc")
                        .font(.system(size: 14))
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.s)
        }

        if server.receivedCount > 0 {
            Section {
                HStack {
                    Label("已接收 \(server.receivedCount) 个文件", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.safe)
                    Spacer()
                }
                if let name = server.lastReceivedName {
                    Text("最近：\(name)")
                        .font(.system(size: 13)).foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }

    private func instructionRow(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Text("\(n)")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.Colors.accent))
            Text(text).font(.system(size: 14)).foregroundStyle(Theme.Colors.primaryText)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
