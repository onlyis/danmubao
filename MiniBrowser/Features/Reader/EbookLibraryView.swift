import SwiftUI

/// 电子书图书馆：列出下载目录里真实的电子书文件（epub / pdf / txt）。
/// 点击：epub → EpubReaderView；pdf → PDFViewerView（已存在）；txt → 内置文本阅读器。
/// 无书时显示空状态。顶部「导入」入口（后续接入文件导入）。
struct EbookLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var books: [EbookFile] = []
    /// 当前要打开的书（以 .fullScreenCover(item:) 呈现对应阅读器）。
    @State private var opened: EbookFile?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    /// 过滤后的列表（按搜索词，忽略大小写）。
    private var filtered: [EbookFile] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return books }
        return books.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        Group {
            if books.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(filtered) { book in
                            Button { opened = book } label: { cover(book) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .searchable(text: $search, prompt: "搜索图书")
        .navigationTitle("图书馆").navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { reload() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    Button { } label: { Label("从文件导入（敬请期待）", systemImage: "folder") }
                } label: { Image(systemName: "plus") }
            }
        }
        .onAppear(perform: reload)
        .fullScreenCover(item: $opened) { book in
            switch book.kind {
            case .epub: EpubReaderView(url: book.url)
            case .pdf:  PDFViewerView(url: book.url)
            case .txt:  TextReaderView(url: book.url)
            }
        }
    }

    /// 扫描下载目录，过滤出 epub/pdf/txt 文件。
    private func reload() {
        books = EbookFile.scan()
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "books.vertical")
                .font(.system(size: 52))
                .foregroundStyle(Theme.Colors.tertiaryText)
            Text("书架空空如也")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.Colors.primaryText)
            Text("下载或导入 EPUB / PDF / TXT 电子书后将在此显示")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 封面

    private func cover(_ book: EbookFile) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [book.color, book.color.opacity(0.7)],
                                     startPoint: .top, endPoint: .bottom))
                .aspectRatio(0.7, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    Text(book.title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .padding(8).lineLimit(4)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(book.kind.label).font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.3), in: Capsule()).padding(6)
                }
                .shadow(color: .black.opacity(0.15), radius: 4, x: 2, y: 3)
            Text(book.title)
                .font(.system(size: 11)).foregroundStyle(Theme.Colors.secondaryText)
                .lineLimit(1)
        }
    }
}

// MARK: - 电子书文件模型

/// 下载目录中的真实电子书文件。
struct EbookFile: Identifiable {
    enum Kind {
        case epub, pdf, txt
        /// 封面右下角格式标。
        var label: String {
            switch self {
            case .epub: return "EPUB"
            case .pdf:  return "PDF"
            case .txt:  return "TXT"
            }
        }
        /// 按扩展名解析；非电子书返回 nil。
        static func from(ext: String) -> Kind? {
            switch ext.lowercased() {
            case "epub": return .epub
            case "pdf":  return .pdf
            case "txt":  return .txt
            default:     return nil
            }
        }
    }

    let id = UUID()
    let url: URL
    let kind: Kind
    var title: String { url.deletingPathExtension().lastPathComponent }
    /// 由书名稳定派生的封面色（同名书每次颜色一致）。
    var color: Color {
        let palette: [UInt] = [0x2C3E50, 0xC0392B, 0xD35400, 0x16A085, 0x8E44AD, 0x2980B9, 0x27AE60]
        let h = abs(title.hashValue)
        return Color(hex: palette[h % palette.count])
    }

    /// 扫描下载目录，过滤出受支持的电子书文件。
    static func scan() -> [EbookFile] {
        let fm = FileManager.default
        let dir = DownloadManager.downloadsDirectory
        guard let urls = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { url -> EbookFile? in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard !isDir, let kind = Kind.from(ext: url.pathExtension) else { return nil }
            return EbookFile(url: url, kind: kind)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

// MARK: - 内置 TXT 阅读器

/// 简单文本阅读器：读本地 txt（按常见编码尝试解码），可调字号。
struct TextReaderView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var content: String?
    @State private var loadError: String?
    @State private var fontSize: CGFloat = 17

    var body: some View {
        NavigationStack {
            Group {
                if let content {
                    ScrollView {
                        Text(content)
                            .font(.system(size: fontSize))
                            .lineSpacing(fontSize * 0.5)
                            .foregroundStyle(Color(hex: 0x2A2A2A))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.Spacing.xl)
                    }
                } else if let loadError {
                    VStack(spacing: Theme.Spacing.m) {
                        Image(systemName: "doc.questionmark")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.Colors.tertiaryText)
                        Text(loadError)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Spacing.xl)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(hex: 0xF3ECD8).ignoresSafeArea())
            .navigationTitle(url.deletingPathExtension().lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { fontSize = min(fontSize + 1, 26) } label: {
                            Label("增大字号", systemImage: "textformat.size.larger")
                        }
                        Button { fontSize = max(fontSize - 1, 13) } label: {
                            Label("减小字号", systemImage: "textformat.size.smaller")
                        }
                    } label: { Image(systemName: "textformat") }
                }
            }
        }
        .onAppear(perform: load)
    }

    /// 读取并解码 txt：依次尝试 UTF-8 / GB18030 / UTF-16，全失败则报错。
    private func load() {
        guard content == nil, loadError == nil else { return }
        guard let data = try? Data(contentsOf: url) else {
            loadError = "无法读取文件：\(url.lastPathComponent)"
            return
        }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let encodings: [String.Encoding] = [.utf8, gb18030, .utf16, .isoLatin1]
        for enc in encodings {
            if let text = String(data: data, encoding: enc) {
                content = text
                return
            }
        }
        loadError = "无法识别文本编码：\(url.lastPathComponent)"
    }
}
