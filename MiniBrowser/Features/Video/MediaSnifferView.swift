import SwiftUI

/// 网页媒体嗅探结果页：列出页面内嗅探到的全部音/视频地址，
/// 每条提供「下载 / 复制链接 / 分享」操作；无结果时给出友好提示。
struct MediaSnifferView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline().padding(.horizontal, Theme.Spacing.l)

            if vm.mediaHits.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.s) {
                        ForEach(vm.mediaHits) { hit in
                            MediaHitRow(hit: hit)
                                .padding(.horizontal, Theme.Spacing.l)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.m)
                }
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    // 顶部标题头：图标 + 标题 + 命中数 + 关闭
    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 19))
                .foregroundStyle(Theme.Colors.accent)
            Text("媒体嗅探")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.primaryText)
            if !vm.mediaHits.isEmpty {
                Text("\(vm.mediaHits.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Theme.Colors.accent, in: Capsule())
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.m)
    }

    // 空结果友好提示
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.m) {
            Spacer()
            Image(systemName: "wave.3.right.circle")
                .font(.system(size: 52))
                .foregroundStyle(Theme.Colors.tertiaryText)
            Text("未嗅探到媒体")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.primaryText)
            Text("当前页面没有可下载的音/视频。\n播放后再试，或在视频出现后重新嗅探。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 单条媒体命中行：标题 + 地址 + 三个操作按钮。
private struct MediaHitRow: View {
    @EnvironmentObject var vm: BrowserViewModel
    let hit: MediaHit

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: hit.kind.symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.Colors.primaryText)
                        .lineLimit(1)
                    Text(hit.url)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(hit.kind.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.Colors.groupedBackground, in: Capsule())
            }

            HStack(spacing: Theme.Spacing.s) {
                actionButton("下载", symbol: "arrow.down.circle", tint: Theme.Colors.accent) {
                    vm.downloadMediaHit(hit)
                }
                actionButton("复制链接", symbol: "doc.on.doc", tint: Theme.Colors.secondaryText) {
                    UIPasteboard.general.string = hit.url
                    vm.showToast("已复制链接", symbol: "doc.on.doc")
                }
                actionButton("分享", symbol: "square.and.arrow.up", tint: Theme.Colors.secondaryText) {
                    vm.shareMediaHit(hit)
                }
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.medium))
    }

    private func actionButton(_ title: String, symbol: String, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
