import SwiftUI
import UniformTypeIdentifiers

/// 书签导入 / 导出：标准 Netscape Bookmark HTML（各浏览器通用格式）。
/// 放在独立文件，避免改 LibraryStore.swift。
extension LibraryStore {

    // MARK: - 导出

    /// 把 library.bookmarks 导出为 Netscape bookmark HTML，写入 Downloads 目录。
    /// 文件夹用 `<DL><DT><H3>` 嵌套，按 parentID 还原层级。失败返回 nil（写盘失败已在内部抛断言）。
    func exportHTML() -> URL? {
        let html = Self.netscapeHTML(from: bookmarks)
        guard let data = html.data(using: .utf8) else {
            // Release 下 assertionFailure 是 no-op，会导致导出静默失败。
            NSLog("[BookmarkPortability] 书签导出 HTML 编码失败 count=%d", bookmarks.count)
            return nil
        }
        let name = "bookmarks-\(Self.exportStamp.string(from: Date())).html"
        let dest = DownloadManager.uniqueDestination(for: name, in: DownloadManager.downloadsDirectory)
        do {
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            // Release 下 assertionFailure 是 no-op，会导致导出静默失败。
            NSLog("[BookmarkPortability] 书签导出写盘失败 dest=%@ error=%@", dest.path, String(describing: error))
            return nil
        }
    }

    private static let exportStamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f
    }()

    /// 生成 Netscape bookmark HTML 文本。
    private static func netscapeHTML(from bookmarks: [Bookmark]) -> String {
        // 按 parentID 分组，保序（与列表展示一致）。
        var children: [UUID?: [Bookmark]] = [:]
        for b in bookmarks { children[b.parentID, default: []].append(b) }

        var out = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <!-- This is an automatically generated file. -->
        <META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>

        """
        appendLevel(parentID: nil, indent: 1, children: children, into: &out)
        out += "</DL><p>\n"
        return out
    }

    /// 递归输出某个父目录下的条目。`indent` 控制缩进层级（与多数浏览器导出对齐）。
    private static func appendLevel(parentID: UUID?, indent: Int,
                                    children: [UUID?: [Bookmark]], into out: inout String) {
        let pad = String(repeating: "    ", count: indent)
        for b in children[parentID] ?? [] {
            if b.isFolder {
                out += "\(pad)<DT><H3>\(escape(b.title))</H3>\n"
                out += "\(pad)<DL><p>\n"
                appendLevel(parentID: b.id, indent: indent + 1, children: children, into: &out)
                out += "\(pad)</DL><p>\n"
            } else {
                out += "\(pad)<DT><A HREF=\"\(escape(b.url))\">\(escape(b.title))</A>\n"
            }
        }
    }

    /// HTML 实体转义（防止标题/网址里的特殊字符破坏结构）。
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - 导入

    /// 从 Netscape bookmark HTML 文件解析书签并追加进 library.bookmarks。
    /// 解析 `<H3>` 文件夹（建立层级）与 `<A HREF=...>文本</A>` 书签。返回导入的书签条数（不含文件夹）。
    func importHTML(from url: URL) -> Int {
        // 处理 iCloud / 文件 App 的安全作用域资源。
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              // 多数书签文件是 UTF-8；个别旧导出用 GBK/Latin1，退化到 isoLatin1 以免整体读不出。
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            // Release 下 assertionFailure 是 no-op，会导致导入静默失败。
            NSLog("[BookmarkPortability] 书签导入无法读取文件 path=%@", url.path)
            return 0
        }

        let parsed = Self.parse(html: html)
        guard !parsed.isEmpty else { return 0 }

        // 一次性追加（单次 didSet → 单次落盘）。新条目置于现有书签之前。
        bookmarks.insert(contentsOf: parsed, at: 0)
        return parsed.filter { !$0.isFolder }.count
    }

    /// 极简解析：扫描 `<DL>`/`</DL>` 维护父目录栈，遇 `<H3>` 入栈新文件夹、遇 `<A HREF>` 建书签。
    private static func parse(html: String) -> [Bookmark] {
        var result: [Bookmark] = []
        var folderStack: [UUID?] = [nil]   // 栈顶为当前父目录，根目录为 nil

        // 逐行扫描，按出现顺序处理标签（Netscape 格式每个条目通常独占一行）。
        let lower = html.lowercased()
        var searchStart = lower.startIndex

        while searchStart < lower.endIndex {
            // 找下一个关注的标签
            guard let tag = nextTag(in: lower, from: searchStart) else { break }
            let range = tag.range
            switch tag.kind {
            case .openDL:
                searchStart = range.upperBound
            case .closeDL:
                if folderStack.count > 1 { folderStack.removeLast() }
                searchStart = range.upperBound
            case .h3:
                // 取 <H3 ...>文本</H3>
                if let (title, after) = extractTag(html: html, lowerHTML: lower,
                                                   openEnd: range.upperBound, closeTag: "</h3>") {
                    let folder = Bookmark(title: cleanup(title).isEmpty ? "新建文件夹" : cleanup(title),
                                          url: "", glyph: "", colorHex: 0x0A84FF,
                                          isFolder: true, parentID: folderStack.last ?? nil)
                    result.append(folder)
                    folderStack.append(folder.id)   // 后续 <DL> 内条目归属此文件夹
                    searchStart = after
                } else {
                    searchStart = range.upperBound
                }
            case .anchor:
                if let href = attribute("href", inTag: html, lowerHTML: lower, tagRange: range),
                   let (text, after) = extractTag(html: html, lowerHTML: lower,
                                                  openEnd: range.upperBound, closeTag: "</a>") {
                    let urlStr = cleanup(href)
                    guard !urlStr.isEmpty else { searchStart = after; continue }
                    let title = cleanup(text)
                    result.append(Bookmark(title: title.isEmpty ? urlStr : title,
                                           url: urlStr,
                                           glyph: String(urlStr.prefix(1)).uppercased(),
                                           colorHex: 0x0A84FF,
                                           parentID: folderStack.last ?? nil))
                    searchStart = after
                } else {
                    searchStart = range.upperBound
                }
            }
        }
        return result
    }

    private enum TagKind { case openDL, closeDL, h3, anchor }
    private struct FoundTag { let kind: TagKind; let range: Range<String.Index> }

    /// 从 `from` 起找到下一个关注标签的起始位置与类型。
    private static func nextTag(in lower: String, from: String.Index) -> FoundTag? {
        var best: FoundTag?
        func consider(_ marker: String, _ kind: TagKind) {
            guard let r = lower.range(of: marker, range: from..<lower.endIndex) else { return }
            if best == nil || r.lowerBound < best!.range.lowerBound {
                // <a 与 <dl 需边界判断，避免 <dl> 命中 <dt
                best = FoundTag(kind: kind, range: r)
            }
        }
        consider("<dl", .openDL)
        consider("</dl", .closeDL)
        consider("<h3", .h3)
        consider("<a ", .anchor)
        return best
    }

    /// 提取 `openEnd`（开标签 `>` 之前的位置）之后、直到 `closeTag` 之间的纯文本，并返回闭标签之后位置。
    private static func extractTag(html: String, lowerHTML: String,
                                   openEnd: String.Index, closeTag: String) -> (String, String.Index)? {
        // openEnd 落在 "<h3 ..." 的 "<" 上；先找该开标签的 ">"
        guard let gt = html.range(of: ">", range: openEnd..<html.endIndex) else { return nil }
        let textStart = gt.upperBound
        guard let close = lowerHTML.range(of: closeTag, range: textStart..<lowerHTML.endIndex) else { return nil }
        let text = String(html[textStart..<close.lowerBound])
        return (text, close.upperBound)
    }

    /// 读取标签内某属性值（如 href）。tagRange 指向 "<a " 的起点。
    private static func attribute(_ name: String, inTag html: String, lowerHTML: String,
                                  tagRange: Range<String.Index>) -> String? {
        guard let gt = html.range(of: ">", range: tagRange.lowerBound..<html.endIndex) else { return nil }
        let tagText = String(html[tagRange.lowerBound..<gt.upperBound])
        let lowerTag = tagText.lowercased()
        guard let attrR = lowerTag.range(of: "\(name)=") else { return nil }
        let afterEq = tagText.index(tagText.startIndex,
                                    offsetBy: lowerTag.distance(from: lowerTag.startIndex, to: attrR.upperBound))
        let rest = tagText[afterEq...]
        guard let quote = rest.first, quote == "\"" || quote == "'" else { return nil }
        let valueStart = rest.index(after: rest.startIndex)
        guard let end = rest[valueStart...].firstIndex(of: quote) else { return nil }
        return String(rest[valueStart..<end])
    }

    /// 反转义 + 去首尾空白。
    private static func cleanup(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 文档选择器：选 .html 文件用于导入书签。
struct BookmarkImportPicker: UIViewControllerRepresentable {
    /// 选中文件回调（主线程）。
    let onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.html, UTType("public.html") ?? .html, .text]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
