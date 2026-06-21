import SwiftUI

/// 生成当前页二维码：展示 vm.currentURL 的二维码，支持保存到相册 / 系统分享 / 复制内容。
struct QRGenerateSheet: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var shareImage: UIImage?

    /// 待编码内容：优先当前页地址，无网页时退回主页占位。
    private var content: String { vm.currentURL.isEmpty ? "https://example.com" : vm.currentURL }
    private var qrImage: UIImage? { QRCode.generate(content) }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                RoundedRectangle(cornerRadius: Theme.Radius.large)
                    .fill(Color.white)
                    .frame(width: 240, height: 240)
                    .overlay {
                        if let img = qrImage {
                            Image(uiImage: img).interpolation(.none).resizable().scaledToFit().padding(18)
                        } else {
                            Image(systemName: "qrcode").resizable().scaledToFit().padding(24).foregroundStyle(.black)
                        }
                    }
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)

                Text(content)
                    .font(.system(size: 14)).foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)

                HStack(spacing: Theme.Spacing.xl) {
                    qrAction("保存图片", "square.and.arrow.down", action: saveToAlbum)
                    qrAction("分享", "square.and.arrow.up", action: share)
                    qrAction("复制内容", "doc.on.doc", action: copyContent)
                }
                Spacer()
            }
            .padding(.top, 40)
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.background.ignoresSafeArea())
            .navigationTitle("二维码").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .sheet(item: Binding(get: { shareImage.map(ShareImageItem.init) },
                                 set: { if $0 == nil { shareImage = nil } })) { item in
                ActivityView(items: [item.image])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - 动作
    /// 保存二维码图片到系统相册。
    private func saveToAlbum() {
        guard let img = qrImage else { vm.showToast("二维码生成失败", symbol: "exclamationmark.circle"); return }
        // UIImageWriteToSavedPhotosAlbum 需主线程；本视图已在主线程。
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        vm.showToast("已保存到相册", symbol: "checkmark.circle.fill")
    }

    /// 系统分享二维码图片。
    private func share() {
        guard let img = qrImage else { vm.showToast("二维码生成失败", symbol: "exclamationmark.circle"); return }
        shareImage = img
    }

    /// 复制被编码的内容文本。
    private func copyContent() {
        UIPasteboard.general.string = content
        vm.showToast("已复制内容", symbol: "doc.on.doc")
    }

    private func qrAction(_ t: String, _ s: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: s).font(.system(size: 20)).foregroundStyle(Theme.Colors.accent)
                    .frame(width: 48, height: 48).background(Circle().fill(Theme.Colors.accent.opacity(0.1)))
                Text(t).font(.system(size: 11)).foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }
}

/// 给 .sheet(item:) 用的可标识分享载体。
private struct ShareImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}
