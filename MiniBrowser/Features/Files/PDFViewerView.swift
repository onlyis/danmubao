import SwiftUI
import PDFKit

/// PDF 阅读器：用 PDFKit 的 PDFView 查看本地 PDF 文件。
/// 由文件列表点击 PDF 或菜单「用阅读器打开」触发（`vm.pdfPreviewURL` 以 .sheet(item:) 呈现）。
struct PDFViewerView: View {
    /// 待查看的 PDF 文件 URL（下载目录内的本地文件）。
    let url: URL
    @Environment(\.dismiss) private var dismiss

    /// 当前文档（加载失败为 nil，渲染错误占位）。
    private var document: PDFDocument? { PDFDocument(url: url) }

    var body: some View {
        NavigationStack {
            Group {
                if let document {
                    PDFKitView(document: document)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    // 加载失败占位（文件损坏 / 非法 PDF）
                    VStack(spacing: Theme.Spacing.m) {
                        Image(systemName: "doc.questionmark")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.Colors.tertiaryText)
                        Text("无法打开此 PDF 文件")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(url.deletingPathExtension().lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
    }
}

/// PDFKit 的 PDFView 的 SwiftUI 包装（连续滚动 + 自适应缩放）。
private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true            // 自适应页宽
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.usePageViewController(false)
        view.backgroundColor = .systemBackground
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        // 文档变化时更新（同一弹层内一般不变，做幂等保护）
        if view.document !== document { view.document = document }
    }
}
