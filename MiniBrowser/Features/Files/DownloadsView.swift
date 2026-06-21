import SwiftUI

/// 下载管理列表：真实 URLSession 下载，显示进度、暂停/继续/删除，完成后可分享。
struct DownloadsView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @EnvironmentObject var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if manager.downloads.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(manager.downloads) { dl in
                        DownloadRow(dl: dl)
                    }
                    .onDelete { idx in
                        idx.map { manager.downloads[$0] }.forEach(manager.remove)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("下载")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button { vm.route = .files } label: { Image(systemName: "folder") }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle").font(.system(size: 46)).foregroundStyle(Theme.Colors.tertiaryText)
            Text("暂无下载").font(.system(size: 16, weight: .medium))
            Text("在网页中长按链接或资源即可下载").font(.system(size: 13)).foregroundStyle(Theme.Colors.secondaryText)
            Button {
                manager.start(urlString: "https://www.bing.com")
            } label: {
                Text("下载示例文件").padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Theme.Colors.accent, in: Capsule()).foregroundStyle(.white)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }
}

private struct DownloadRow: View {
    @EnvironmentObject var manager: DownloadManager
    @ObservedObject var dl: LiveDownload

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            SiteIcon(glyph: "", color: tint, symbol: symbol, size: 40, corner: 9)
            VStack(alignment: .leading, spacing: 6) {
                Text(dl.fileName).font(.system(size: 14)).foregroundStyle(Theme.Colors.primaryText).lineLimit(1)
                switch dl.state {
                case .downloading:
                    ProgressView(value: dl.progress).tint(Theme.Colors.accent)
                    Text("\(dl.sizeText) · \(Int(dl.progress * 100))%")
                        .font(.system(size: 11)).foregroundStyle(Theme.Colors.secondaryText)
                case .paused:
                    ProgressView(value: dl.progress).tint(Theme.Colors.secondaryText)
                    Text("\(dl.sizeText) · 已暂停").font(.system(size: 11)).foregroundStyle(Theme.Colors.secondaryText)
                case .completed:
                    Text("\(dl.sizeText) · 已完成").font(.system(size: 11)).foregroundStyle(Theme.Colors.safe)
                case .failed(let msg):
                    Text("下载失败：\(msg)").font(.system(size: 11)).foregroundStyle(Theme.Colors.danger).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.vertical, 4)
    }

    private var tint: Color {
        switch dl.state { case .failed: return Theme.Colors.danger; default: return Theme.Colors.accent }
    }
    private var symbol: String {
        switch dl.state {
        case .completed: return "checkmark"
        case .failed: return "exclamationmark.triangle.fill"
        default: return "arrow.down"
        }
    }

    @ViewBuilder private var trailing: some View {
        switch dl.state {
        case .downloading:
            Button { manager.pause(dl) } label: {
                Image(systemName: "pause.circle").font(.system(size: 24)).foregroundStyle(Theme.Colors.accent)
            }.buttonStyle(.plain)
        case .paused:
            Button { manager.resume(dl) } label: {
                Image(systemName: "play.circle").font(.system(size: 24)).foregroundStyle(Theme.Colors.accent)
            }.buttonStyle(.plain)
        case .failed:
            Button { manager.remove(dl); manager.start(urlString: dl.sourceURL.absoluteString) } label: {
                Image(systemName: "arrow.clockwise.circle").font(.system(size: 24)).foregroundStyle(Theme.Colors.accent)
            }.buttonStyle(.plain)
        case .completed:
            Menu {
                if let url = dl.localURL {
                    ShareLink(item: url) { Label("分享", systemImage: "square.and.arrow.up") }
                }
                Button(role: .destructive) { manager.remove(dl) } label: { Label("删除", systemImage: "trash") }
            } label: { Image(systemName: "ellipsis").font(.system(size: 18)).foregroundStyle(Theme.Colors.secondaryText) }
        }
    }
}

/// 下载确认弹窗：可编辑地址，确认后发起真实下载。
struct DownloadConfirmSheet: View {
    @EnvironmentObject var vm: BrowserViewModel
    @EnvironmentObject var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var urlText: String = ""

    private var fileName: String {
        URL(string: urlText.hasPrefix("http") ? urlText : "https://" + urlText)
            .map(DownloadManager.fileName) ?? "download.bin"
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Capsule().fill(Theme.Colors.separator).frame(width: 36, height: 5).padding(.top, 8)
            Text("下载文件").font(.system(size: 17, weight: .semibold))

            HStack(spacing: Theme.Spacing.m) {
                SiteIcon(glyph: "", color: Theme.Colors.accent, symbol: "arrow.down.doc.fill", size: 48, corner: 11)
                VStack(alignment: .leading, spacing: 4) {
                    Text(fileName).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Text("将保存到「下载」").font(.system(size: 12)).foregroundStyle(Theme.Colors.secondaryText)
                }
                Spacer()
            }
            .padding(Theme.Spacing.m)
            .background(Theme.Colors.groupedBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.medium))

            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "link").foregroundStyle(Theme.Colors.secondaryText)
                TextField("下载地址", text: $urlText)
                    .font(.system(size: 14)).autocorrectionDisabled().textInputAutocapitalization(.never)
            }
            .padding(.horizontal, Theme.Spacing.m).frame(height: 44)
            .background(Theme.Colors.groupedBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.small))

            HStack(spacing: Theme.Spacing.m) {
                Button { dismiss() } label: {
                    Text("取消").frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Theme.Colors.groupedBackground, in: Capsule())
                        .foregroundStyle(Theme.Colors.primaryText)
                }
                Button {
                    manager.start(urlString: urlText)
                    dismiss()
                    vm.route = .downloads
                } label: {
                    Text("下载").frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(urlText.isEmpty ? Theme.Colors.accent.opacity(0.4) : Theme.Colors.accent, in: Capsule())
                        .foregroundStyle(.white).fontWeight(.semibold)
                }
                .disabled(urlText.isEmpty)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .onAppear { if urlText.isEmpty { urlText = vm.currentURL.isEmpty ? "https://www.bing.com" : vm.currentURL } }
    }
}
