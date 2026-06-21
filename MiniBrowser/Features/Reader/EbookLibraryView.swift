import SwiftUI

/// 电子书图书馆：封面网格 + 最近阅读 + 导入。支持 txt/pdf/epub/mobi 等。
struct EbookLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    struct Book: Identifiable { let id = UUID(); var title: String; var format: String; var progress: Double; var color: Color }
    private let books: [Book] = [
        .init(title: "三体", format: "EPUB", progress: 0.62, color: Color(hex: 0x2C3E50)),
        .init(title: "活着", format: "TXT", progress: 0.18, color: Color(hex: 0xC0392B)),
        .init(title: "百年孤独", format: "MOBI", progress: 0.91, color: Color(hex: 0xD35400)),
        .init(title: "SwiftUI 实战", format: "PDF", progress: 0.40, color: Color(hex: 0x16A085)),
        .init(title: "人类简史", format: "AZW3", progress: 0.05, color: Color(hex: 0x8E44AD)),
        .init(title: "未来简史", format: "EPUB", progress: 0, color: Color(hex: 0x2980B9)),
    ]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(books) { book in
                    NavigationLink { EbookReaderView(title: book.title) } label: { cover(book) }
                        .buttonStyle(.plain)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .searchable(text: $search, prompt: "搜索图书")
        .navigationTitle("图书馆").navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { } label: { Label("从文件导入", systemImage: "folder") }
                    Button { } label: { Label("Wi-Fi 传输", systemImage: "wifi") }
                    Button { } label: { Label("按名称排序", systemImage: "textformat") }
                    Button { } label: { Label("按最近阅读排序", systemImage: "clock") }
                } label: { Image(systemName: "plus") }
            }
        }
    }

    private func cover(_ book: Book) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [book.color, book.color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .aspectRatio(0.7, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    Text(book.title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .padding(8).lineLimit(3)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(book.format).font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.3), in: Capsule()).padding(6)
                }
                .shadow(color: .black.opacity(0.15), radius: 4, x: 2, y: 3)
            ProgressView(value: book.progress).tint(Theme.Colors.accent).scaleEffect(y: 0.6)
            Text(book.progress == 0 ? "未读" : "\(Int(book.progress * 100))%")
                .font(.system(size: 10)).foregroundStyle(Theme.Colors.secondaryText)
        }
    }
}

/// 电子书阅读器
struct EbookReaderView: View {
    let title: String
    @State private var showBar = true
    @State private var fontSize: CGFloat = 18
    var body: some View {
        ZStack {
            Color(hex: 0xF3ECD8).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("第一章").font(.system(size: fontSize + 6, weight: .bold)).foregroundStyle(Color(hex: 0x222222))
                    ForEach(0..<6, id: \.self) { i in
                        Text(ReadingModeView.paragraph(i))
                            .font(.system(size: fontSize)).lineSpacing(fontSize * 0.5)
                            .foregroundStyle(Color(hex: 0x2A2A2A))
                    }
                }.padding(Theme.Spacing.xl)
            }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { } label: { Label("目录", systemImage: "list.bullet") }
                    Button { } label: { Label("书签", systemImage: "bookmark") }
                    Button { fontSize = min(fontSize + 1, 26) } label: { Label("增大字号", systemImage: "textformat.size.larger") }
                    Button { fontSize = max(fontSize - 1, 14) } label: { Label("减小字号", systemImage: "textformat.size.smaller") }
                } label: { Image(systemName: "textformat") }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Image(systemName: "sun.min")
                Slider(value: .constant(0.7))
                Image(systemName: "sun.max")
            }
            .font(.system(size: 14)).foregroundStyle(Color(hex: 0x666666))
            .padding(.horizontal, Theme.Spacing.xl).padding(.vertical, 10)
            .background(Color(hex: 0xF3ECD8))
        }
    }
}
