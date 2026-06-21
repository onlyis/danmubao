import SwiftUI
import WebKit

/// EPUB 解析错误（显式抛出，不静默吞）。错误信息带足够上下文便于调试。
enum EpubError: LocalizedError {
    case unzipFailed(name: String, underlying: String)
    case containerMissing(at: String)
    case opfPathNotFound(container: String)
    case opfMissing(at: String)
    case spineEmpty(opf: String)

    var errorDescription: String? {
        switch self {
        case .unzipFailed(let name, let underlying): return "解压 EPUB 失败 \(name)：\(underlying)"
        case .containerMissing(let at): return "无法解析 EPUB：缺少 META-INF/container.xml（\(at)）"
        case .opfPathNotFound(let container): return "无法解析 EPUB：container.xml 未指向 OPF（\(container)）"
        case .opfMissing(let at): return "无法解析 EPUB：找不到 OPF 文件（\(at)）"
        case .spineEmpty(let opf): return "无法解析 EPUB：spine 为空，无可读章节（\(opf)）"
        }
    }
}

/// 解析后的 EPUB：解压根目录 + 有序章节文件 URL + 书名。
struct ParsedEpub {
    /// 解压后的临时根目录（loadFileURL 的读权限根）。
    let unpackedRoot: URL
    /// 按 spine 顺序排列的章节 XHTML 文件 URL。
    let chapters: [URL]
    /// 书名（取自 OPF 的 dc:title，缺省用文件名）。
    let title: String
}

/// EPUB 解析器：epub 即 zip，复用 ArchiveStore.unzip。
/// 流程：解压到 caches 临时目录 → 读 META-INF/container.xml 取 OPF 路径 → 解析 OPF 的 manifest+spine → 得到有序章节 XHTML。
@MainActor
enum EpubParser {

    /// EPUB 解压临时根（caches/EpubUnpacked），每本书一个以源文件名+大小命名的子目录（同书复用，避免重复解压）。
    static func unpackBase() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EpubUnpacked", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// 解析指定 epub 文件，得到可呈现的章节列表。出错显式抛出 EpubError。
    static func parse(_ epubURL: URL) throws -> ParsedEpub {
        let fm = FileManager.default
        // 以「文件名-大小」命名解压目录，相同文件复用、不同内容不冲突。
        let size = (try? epubURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let key = epubURL.deletingPathExtension().lastPathComponent + "-\(size)"
        let dest = unpackBase().appendingPathComponent(key, isDirectory: true)

        // 已解压过（存在 META-INF）则复用，否则解压。
        let containerURL = dest.appendingPathComponent("META-INF/container.xml")
        if !fm.fileExists(atPath: containerURL.path) {
            // 清理半成品再重解，避免脏目录。
            try? fm.removeItem(at: dest)
            do {
                try ArchiveStore.unzip(epubURL, to: dest)
            } catch {
                throw EpubError.unzipFailed(name: epubURL.lastPathComponent,
                                            underlying: error.localizedDescription)
            }
        }

        guard let containerData = try? Data(contentsOf: containerURL) else {
            throw EpubError.containerMissing(at: containerURL.path)
        }

        // 1) container.xml → rootfile full-path（OPF 相对路径）
        guard let opfRelPath = parseContainer(containerData) else {
            throw EpubError.opfPathNotFound(container: containerURL.path)
        }
        let opfURL = dest.appendingPathComponent(opfRelPath)
        guard let opfData = try? Data(contentsOf: opfURL) else {
            throw EpubError.opfMissing(at: opfURL.path)
        }

        // 2) OPF → manifest(id→href) + spine(idref 顺序) + title
        let opfBaseDir = opfURL.deletingLastPathComponent()
        let parsed = parseOPF(opfData)
        var chapters: [URL] = []
        for idref in parsed.spine {
            guard let href = parsed.manifest[idref] else { continue }
            // href 相对于 OPF 所在目录；URL 解码处理空格/中文。
            let decoded = href.removingPercentEncoding ?? href
            let url = opfBaseDir.appendingPathComponent(decoded)
            if fm.fileExists(atPath: url.path) { chapters.append(url) }
        }
        guard !chapters.isEmpty else {
            throw EpubError.spineEmpty(opf: opfURL.path)
        }

        let title = parsed.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = (title?.isEmpty == false ? title! : epubURL.deletingPathExtension().lastPathComponent)
        return ParsedEpub(unpackedRoot: dest, chapters: chapters, title: finalTitle)
    }

    // MARK: - container.xml 解析

    /// 取 <rootfile full-path="...">，即 OPF 相对路径。
    private static func parseContainer(_ data: Data) -> String? {
        let delegate = ContainerXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.opfPath
    }

    // MARK: - OPF 解析

    private struct OPFResult {
        var manifest: [String: String] = [:]   // id → href
        var spine: [String] = []                // 有序 idref
        var title: String?
    }

    private static func parseOPF(_ data: Data) -> OPFResult {
        let delegate = OPFXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return OPFResult(manifest: delegate.manifest, spine: delegate.spine, title: delegate.title)
    }
}

/// container.xml 的 SAX 委托：抓 rootfile/@full-path。
private final class ContainerXMLDelegate: NSObject, XMLParserDelegate {
    var opfPath: String?

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName.lowercased().hasSuffix("rootfile"), opfPath == nil {
            opfPath = attributeDict["full-path"] ?? attributeDict["fullpath"]
        }
    }
}

/// OPF 的 SAX 委托：抓 manifest item(id/href)、spine itemref(idref) 顺序、dc:title。
private final class OPFXMLDelegate: NSObject, XMLParserDelegate {
    var manifest: [String: String] = [:]
    var spine: [String] = []
    var title: String?

    private var inTitle = false
    private var titleBuffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let name = elementName.lowercased()
        // 命名空间前缀剥离（opf:item / dc:title 等）。
        let local = name.contains(":") ? String(name.split(separator: ":").last!) : name
        switch local {
        case "item":
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = href
            }
        case "itemref":
            if let idref = attributeDict["idref"] {
                // linear="no" 也保留（部分书把正文标 no），顺序以 spine 为准。
                spine.append(idref)
            }
        case "title":
            inTitle = true
            titleBuffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTitle { titleBuffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let local = name.contains(":") ? String(name.split(separator: ":").last!) : name
        if local == "title", inTitle {
            if title == nil { title = titleBuffer }
            inTitle = false
        }
    }
}

// MARK: - 阅读器视图

/// EPUB 阅读器：用 WKWebView 按 spine 顺序加载本地解压后的 XHTML 章节。
/// - 上一章 / 下一章切换；字号调节（注入 CSS 缩放）；底部进度（第 n/共 m 章）。
/// - 本地解压文件读取用 `loadFileURL(_:allowingReadAccessTo:)`，读权限根设为整个解压目录，
///   这样章节内引用的 CSS/图片等相对资源也能被 WKWebView 读到。
struct EpubReaderView: View {
    /// 待阅读的 epub 文件 URL（下载目录内）。
    let url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var parsed: ParsedEpub?
    @State private var parseError: String?
    @State private var index = 0
    @State private var fontPercent: Int = 100   // 字号百分比（80…180）
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Group {
                if let parsed {
                    reader(parsed)
                } else if let parseError {
                    errorState(parseError)
                } else {
                    ProgressView("正在解析 EPUB…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(hex: 0xF3ECD8).ignoresSafeArea())
            .navigationTitle(parsed?.title ?? url.deletingPathExtension().lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { fontPercent = min(fontPercent + 10, 180) } label: {
                            Label("增大字号", systemImage: "textformat.size.larger")
                        }
                        Button { fontPercent = max(fontPercent - 10, 80) } label: {
                            Label("减小字号", systemImage: "textformat.size.smaller")
                        }
                    } label: { Image(systemName: "textformat") }
                    .disabled(parsed == nil)
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func reader(_ parsed: ParsedEpub) -> some View {
        VStack(spacing: 0) {
            EpubChapterWebView(fileURL: parsed.chapters[index],
                               readAccessRoot: parsed.unpackedRoot,
                               fontPercent: fontPercent)
                .ignoresSafeArea(edges: .horizontal)
            chapterBar(total: parsed.chapters.count)
        }
    }

    /// 底部章节导航条：上一章 / 进度 / 下一章。
    private func chapterBar(total: Int) -> some View {
        HStack(spacing: Theme.Spacing.l) {
            Button {
                if index > 0 { index -= 1 }
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
            }
            .disabled(index == 0)

            VStack(spacing: 2) {
                Text("第 \(index + 1) / \(total) 章")
                    .font(.system(size: 13, weight: .medium))
                ProgressView(value: Double(index + 1), total: Double(total))
                    .tint(Theme.Colors.accent)
            }

            Button {
                if index < total - 1 { index += 1 }
            } label: {
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .semibold))
            }
            .disabled(index >= total - 1)
        }
        .foregroundStyle(Color(hex: 0x444444))
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, 10)
        .background(Color(hex: 0xF3ECD8))
        .overlay(alignment: .top) { Rectangle().fill(.black.opacity(0.08)).frame(height: Theme.Size.hairline) }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "book.closed")
                .font(.system(size: 44))
                .foregroundStyle(Theme.Colors.tertiaryText)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 解析 EPUB（解压 + 解析 OPF），失败时显式给出错误文案。
    private func load() async {
        do {
            parsed = try EpubParser.parse(url)
        } catch {
            parseError = (error as? EpubError)?.errorDescription ?? "无法解析 EPUB：\(error.localizedDescription)"
        }
    }
}

/// 单章 WKWebView 包装：loadFileURL 加载本地 XHTML，注入字号 CSS。
private struct EpubChapterWebView: UIViewRepresentable {
    let fileURL: URL
    /// 允许读取的根目录（解压根），保证章节引用的相对资源可读。
    let readAccessRoot: URL
    let fontPercent: Int

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 注入字号缩放 + 阅读排版样式（页边距、行距、不横向溢出）。
        config.userContentController.addUserScript(styleScript(fontPercent))
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = UIColor(Color(hex: 0xF3ECD8))
        webView.isOpaque = false
        webView.scrollView.backgroundColor = UIColor(Color(hex: 0xF3ECD8))
        webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessRoot)
        context.coordinator.loadedURL = fileURL
        context.coordinator.fontPercent = fontPercent
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 章节切换：重新 loadFileURL（仍以解压根为读权限根）。
        if context.coordinator.loadedURL != fileURL {
            // 字号脚本只在 makeUIView 注入；切章后通过 evaluateJavaScript 再设一次（见 didFinish 不可控，直接重注）。
            webView.configuration.userContentController.removeAllUserScripts()
            webView.configuration.userContentController.addUserScript(styleScript(fontPercent))
            webView.loadFileURL(fileURL, allowingReadAccessTo: readAccessRoot)
            context.coordinator.loadedURL = fileURL
            context.coordinator.fontPercent = fontPercent
            return
        }
        // 仅字号变化：直接改 documentElement 的字号，无需重载。
        if context.coordinator.fontPercent != fontPercent {
            context.coordinator.fontPercent = fontPercent
            webView.evaluateJavaScript("document.documentElement.style.fontSize='\(fontPercent)%';", completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedURL: URL?
        var fontPercent: Int = 100
    }

    /// 文档开始时注入的排版样式（字号百分比 + 阅读友好的页边距/行距）。
    private func styleScript(_ percent: Int) -> WKUserScript {
        let css = """
        html{font-size:\(percent)%;-webkit-text-size-adjust:none;}
        body{margin:16px 18px;line-height:1.7;word-wrap:break-word;background:transparent;color:#2A2A2A;}
        img{max-width:100% !important;height:auto !important;}
        """
        let js = """
        (function(){
          var s=document.createElement('style');
          s.textContent=`\(css)`;
          (document.head||document.documentElement).appendChild(s);
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }
}
