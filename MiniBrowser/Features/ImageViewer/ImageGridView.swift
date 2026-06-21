import SwiftUI

/// 看图模式：展示从当前网页提取的真实图片，网格 + 多选批量操作。
/// 无页面图片（如主页进入）时回退为占位色块演示。
struct ImageGridView: View {
    @EnvironmentObject var vm: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selecting = false
    @State private var selected: Set<Int> = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)
    private let placeholderColors: [Color] = [0x4A90D9, 0xFF7A59, 0x34C759, 0xAF52DE, 0xFF375F, 0xFF9500,
                                              0x5AC8FA, 0x5856D6, 0x2D963D, 0xE6162D, 0x0A84FF, 0xFB7299].map { Color(hex: $0) }

    private var images: [String] { vm.pageImages }
    private var count: Int { images.isEmpty ? placeholderColors.count : images.count }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(0..<count, id: \.self) { i in
                    ZStack(alignment: .topTrailing) {
                        cell(i)
                        if selecting {
                            Image(systemName: selected.contains(i) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20)).foregroundStyle(selected.contains(i) ? Theme.Colors.accent : .white)
                                .padding(6).shadow(radius: 2)
                        }
                    }
                    .clipped()
                    .onTapGesture { if selecting { toggle(i) } }
                }
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .navigationTitle("网页图片 (\(count))").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button(selecting ? "取消" : "完成") { selecting ? (selecting = false) : dismiss() } }
            ToolbarItem(placement: .topBarTrailing) { Button(selecting ? "全选" : "选择") { selecting ? selectAll() : (selecting = true) } }
        }
        .safeAreaInset(edge: .bottom) {
            if selecting {
                HStack(spacing: Theme.Spacing.xl * 2) {
                    Button { saveSelected() } label: { bottomOp("保存", "square.and.arrow.down") }
                    ShareLink(items: selectedURLs) { bottomOp("分享", "square.and.arrow.up") }
                        .disabled(selectedURLs.isEmpty)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(.bar)
            }
        }
    }

    /// 选中项里真实可用的远程图片地址（占位演示模式无地址）
    private var selectedURLs: [URL] {
        selected.compactMap { i in images.indices.contains(i) ? URL(string: images[i]) : nil }
    }

    private func saveSelected() {
        let urls = selectedURLs
        guard !urls.isEmpty else { vm.showToast("没有可保存的图片", symbol: "exclamationmark.circle"); return }
        vm.showToast("正在保存 \(urls.count) 张…", symbol: "square.and.arrow.down")
        ImageSaver.saveToAlbum(urls) { saved in
            vm.showToast(saved > 0 ? "已保存 \(saved) 张到相册" : "保存失败",
                         symbol: saved > 0 ? "checkmark.circle.fill" : "exclamationmark.circle")
        }
        selecting = false; selected = []
    }

    @ViewBuilder
    private func cell(_ i: Int) -> some View {
        if images.isEmpty {
            LinearGradient(colors: [placeholderColors[i], placeholderColors[i].opacity(0.5)],
                           startPoint: .top, endPoint: .bottom)
                .aspectRatio(1, contentMode: .fill)
                .overlay { Image(systemName: "photo").font(.system(size: 22)).foregroundStyle(.white.opacity(0.7)) }
        } else {
            Color.clear.aspectRatio(1, contentMode: .fit)
                .overlay {
                    AsyncImage(url: URL(string: images[i])) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        case .failure:
                            Theme.Colors.groupedBackground.overlay {
                                Image(systemName: "photo").foregroundStyle(Theme.Colors.tertiaryText)
                            }
                        default:
                            Theme.Colors.groupedBackground.overlay { ProgressView() }
                        }
                    }
                }
                .clipped()
        }
    }

    private func toggle(_ i: Int) { if selected.contains(i) { selected.remove(i) } else { selected.insert(i) } }
    private func selectAll() { selected = Set(0..<count) }
    private func bottomOp(_ t: String, _ s: String, tint: Color = Theme.Colors.accent) -> some View {
        VStack(spacing: 4) {
            Image(systemName: s).font(.system(size: 20)).foregroundStyle(tint)
            Text("\(t)\(selected.isEmpty ? "" : " \(selected.count)")").font(.system(size: 11)).foregroundStyle(Theme.Colors.secondaryText)
        }
    }
}
