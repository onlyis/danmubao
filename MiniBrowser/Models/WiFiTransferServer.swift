import Foundation
import Network

/// Wi-Fi 文件传输：在局域网起一个最小 HTTP 服务，
/// 让同一 Wi-Fi 下的电脑/手机用浏览器把文件上传到下载目录。
///
/// 设计：
/// - 用 `Network.framework` 的 `NWListener`（TCP）监听端口（默认 8080，被占用则自增重试）。
/// - 仅实现两条路由：`GET /` 返回上传页（含 `multipart/form-data` 表单）；
///   `POST /upload` 解析 multipart 取「文件名 + 内容」存到 `DownloadManager.downloadsDirectory`（唯一命名）。
/// - 用 `getifaddrs` 取 en0 的 IPv4 组成 `http://IP:PORT`。
/// - `@MainActor` 管理对外状态（运行态/URL/已接收文件数）；网络回调在内部队列，回主线程更新。
///
/// 错误显式抛出，不静默吞；状态机简单：未运行 / 启动中 / 运行中(带 URL) / 出错(带文案)。
@MainActor
final class WiFiTransferServer: ObservableObject {

    /// 运行状态。
    enum Status: Equatable {
        case stopped
        case starting
        case running(url: String)
        case failed(String)
    }

    @Published private(set) var status: Status = .stopped
    /// 已成功接收的文件数（用于界面提示）。
    @Published private(set) var receivedCount: Int = 0
    /// 最近一次接收到的文件名（界面提示）。
    @Published private(set) var lastReceivedName: String?

    /// 当前访问 URL（运行时有值）。
    var accessURL: String? {
        if case let .running(url) = status { return url }
        return nil
    }

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    // MARK: - 内部

    private var listener: NWListener?
    /// 所有连接的处理队列（串行即可，单连接吞吐足够文件上传）。
    private let queue = DispatchQueue(label: "com.minibrowser.wifitransfer")
    /// 端口起始值与最大重试次数（端口被占用时自增）。
    private let startPort: UInt16 = 8080
    private let maxPortTries = 20

    // MARK: - 生命周期

    /// 启动服务：尝试从 startPort 起逐个端口绑定，直到成功或耗尽重试。
    func start() {
        if case .running = status { return }
        if case .starting = status { return }
        status = .starting
        receivedCount = 0
        lastReceivedName = nil
        bind(port: startPort, attempt: 0)
    }

    /// 递归尝试绑定端口；失败（端口占用等）时自增端口重试。
    private func bind(port: UInt16, attempt: Int) {
        guard attempt < maxPortTries else {
            status = .failed("无法绑定端口（\(startPort)…\(startPort &+ UInt16(maxPortTries))），请稍后再试")
            return
        }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            status = .failed("非法端口：\(port)")
            return
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let newListener: NWListener
        do {
            newListener = try NWListener(using: params, on: nwPort)
        } catch {
            // 创建失败（多为端口占用），换下一个端口。
            bind(port: port &+ 1, attempt: attempt + 1)
            return
        }

        newListener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    let ip = Self.localIPAddress() ?? "127.0.0.1"
                    self.status = .running(url: "http://\(ip):\(port)")
                case let .failed(error):
                    // ready 之前失败 → 尝试下一个端口；ready 之后失败 → 报错。
                    if case .running = self.status {
                        self.status = .failed("服务已停止：\(error.localizedDescription)")
                        self.stop()
                    } else {
                        self.listener?.cancel()
                        self.listener = nil
                        self.bind(port: port &+ 1, attempt: attempt + 1)
                    }
                case .cancelled:
                    if case .failed = self.status {} else { self.status = .stopped }
                default:
                    break
                }
            }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        listener = newListener
        newListener.start(queue: queue)
    }

    /// 停止服务，释放监听与端口。
    func stop() {
        listener?.cancel()
        listener = nil
        if case .failed = status {} else { status = .stopped }
    }

    deinit {
        listener?.cancel()
    }

    // MARK: - 连接处理

    private nonisolated func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, accumulated: Data())
    }

    /// 持续接收，直到拿到完整 HTTP 请求（含按 Content-Length 的请求体）。
    private nonisolated func receive(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }

            var buffer = accumulated
            if let data { buffer.append(data) }

            if let error {
                // 接收出错：直接关闭连接，不静默继续。
                connection.cancel()
                return
            }

            // 找请求头与请求体的分界 \r\n\r\n。
            guard let headerEnd = Self.range(of: Self.crlfcrlf, in: buffer) else {
                if isComplete { connection.cancel() }
                else { self.receive(on: connection, accumulated: buffer) }
                return
            }

            let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
            let bodyStart = headerEnd.upperBound
            let headerText = String(decoding: headerData, as: UTF8.self)
            let contentLength = Self.contentLength(in: headerText)
            let bodyReceived = buffer.count - bodyStart

            // 请求体还没收全 → 继续收。
            if bodyReceived < contentLength, !isComplete {
                self.receive(on: connection, accumulated: buffer)
                return
            }

            let body = buffer.subdata(in: bodyStart..<min(buffer.count, bodyStart + max(0, contentLength)))
            self.respond(to: connection, headerText: headerText, body: body)
        }
    }

    /// 根据请求行分发路由并回写响应。
    private nonisolated func respond(to connection: NWConnection, headerText: String, body: Data) {
        let requestLine = headerText.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
        let parts = requestLine.split(separator: " ")
        let method = parts.first.map(String.init) ?? "GET"
        let path = parts.count > 1 ? String(parts[1]) : "/"

        if method == "POST", path.hasPrefix("/upload") {
            handleUpload(connection: connection, headerText: headerText, body: body)
        } else {
            let html = Self.uploadPageHTML()
            sendHTML(html, on: connection, statusCode: "200 OK")
        }
    }

    /// 处理上传：从 Content-Type 取 boundary，解析 multipart，落盘。
    private nonisolated func handleUpload(connection: NWConnection, headerText: String, body: Data) {
        guard let boundary = Self.boundary(in: headerText) else {
            sendHTML(Self.resultPageHTML(success: false, message: "请求缺少 multipart 边界（boundary）"),
                     on: connection, statusCode: "400 Bad Request")
            return
        }

        let files = Self.parseMultipart(body: body, boundary: boundary)
        guard !files.isEmpty else {
            sendHTML(Self.resultPageHTML(success: false, message: "未在表单中找到文件"),
                     on: connection, statusCode: "400 Bad Request")
            return
        }

        var savedNames: [String] = []
        var failure: String?
        for file in files {
            let safeName = Self.sanitize(file.filename)
            let dest = DownloadManager.uniqueDestination(for: safeName, in: DownloadManager.downloadsDirectory)
            do {
                try file.content.write(to: dest, options: .atomic)
                savedNames.append(dest.lastPathComponent)
            } catch {
                failure = "保存「\(safeName)」失败：\(error.localizedDescription)"
                break
            }
        }

        if let failure {
            sendHTML(Self.resultPageHTML(success: false, message: failure),
                     on: connection, statusCode: "500 Internal Server Error")
            return
        }

        // 回主线程更新计数与界面提示。
        Task { @MainActor in
            self.receivedCount += savedNames.count
            self.lastReceivedName = savedNames.last
        }
        let msg = savedNames.count == 1 ? "已接收：\(savedNames[0])" : "已接收 \(savedNames.count) 个文件"
        sendHTML(Self.resultPageHTML(success: true, message: msg), on: connection, statusCode: "200 OK")
    }

    // MARK: - 发送响应

    private nonisolated func sendHTML(_ html: String, on connection: NWConnection, statusCode: String) {
        let bodyData = Data(html.utf8)
        var response = "HTTP/1.1 \(statusCode)\r\n"
        response += "Content-Type: text/html; charset=utf-8\r\n"
        response += "Content-Length: \(bodyData.count)\r\n"
        response += "Connection: close\r\n"
        response += "\r\n"
        var out = Data(response.utf8)
        out.append(bodyData)
        connection.send(content: out, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - multipart 解析（难点）

    /// 解析结果：一个上传文件。
    struct UploadedFile {
        let filename: String
        let content: Data
    }

    /// 解析 `multipart/form-data` 请求体，提取所有带 filename 的 part。
    ///
    /// 结构：每个 part 以 `--boundary\r\n` 开头，含若干 header 行，空行后是内容，
    /// 直到下一个 `\r\n--boundary`。最后是 `--boundary--`。
    /// 这里按字节查找，避免把二进制内容当文本破坏。
    nonisolated static func parseMultipart(body: Data, boundary: String) -> [UploadedFile] {
        let delimiter = Data("--\(boundary)".utf8)
        let crlf = Data("\r\n".utf8)
        let headerSep = Data("\r\n\r\n".utf8)

        var results: [UploadedFile] = []
        // 找到所有 delimiter 位置，相邻两个之间即一个 part。
        var ranges: [Range<Int>] = []
        var searchStart = body.startIndex
        while let r = range(of: delimiter, in: body, from: searchStart) {
            ranges.append(r)
            searchStart = r.upperBound
        }
        guard ranges.count >= 2 else { return [] }

        for i in 0..<(ranges.count - 1) {
            // part 内容区间：当前 delimiter 之后到下一个 delimiter 之前。
            var partStart = ranges[i].upperBound
            let partEnd = ranges[i + 1].lowerBound
            guard partStart < partEnd else { continue }

            // delimiter 后通常跟 \r\n（若是 "--" 结束标记则跳过）。
            if let crlfR = range(of: crlf, in: body, from: partStart), crlfR.lowerBound == partStart {
                partStart = crlfR.upperBound
            } else {
                // 形如 "--boundary--" 的结束标记，无内容。
                continue
            }
            guard partStart < partEnd else { continue }

            let partData = body.subdata(in: partStart..<partEnd)
            guard let sepRange = range(of: headerSep, in: partData, from: partData.startIndex) else { continue }

            let headerData = partData.subdata(in: partData.startIndex..<sepRange.lowerBound)
            let headerString = String(decoding: headerData, as: UTF8.self)
            guard let filename = filename(inPartHeader: headerString) else { continue }

            // 内容：分隔空行之后，去掉结尾的 \r\n（part 内容与下一个 delimiter 之间固定有一个 \r\n）。
            let contentStart = sepRange.upperBound
            var contentEnd = partData.endIndex
            // 去掉末尾 \r\n
            if contentEnd - contentStart >= 2 {
                let tail = partData.subdata(in: (contentEnd - 2)..<contentEnd)
                if tail == crlf { contentEnd -= 2 }
            }
            guard contentStart <= contentEnd else { continue }
            let content = partData.subdata(in: contentStart..<contentEnd)
            let name = filename.isEmpty ? "upload-\(Int(Date().timeIntervalSince1970)).bin" : filename
            results.append(UploadedFile(filename: name, content: content))
        }
        return results
    }

    /// 从 part 头里解析 Content-Disposition 的 filename。
    nonisolated static func filename(inPartHeader header: String) -> String? {
        for line in header.split(separator: "\r\n") {
            let lower = line.lowercased()
            guard lower.hasPrefix("content-disposition") else { continue }
            // 形如：Content-Disposition: form-data; name=\"file\"; filename=\"a b.png\"
            guard let r = line.range(of: "filename=") else { return nil }
            var value = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            // 取引号内或到分号止。
            if value.hasPrefix("\"") {
                value.removeFirst()
                if let end = value.firstIndex(of: "\"") { value = String(value[..<end]) }
            } else if let semi = value.firstIndex(of: ";") {
                value = String(value[..<semi])
            }
            let decoded = value.removingPercentEncoding ?? value
            return decoded.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    // MARK: - HTTP 头解析

    nonisolated static let crlfcrlf = Data("\r\n\r\n".utf8)

    nonisolated static func contentLength(in headerText: String) -> Int {
        for line in headerText.split(separator: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let v = line.split(separator: ":", maxSplits: 1).last ?? ""
                return Int(v.trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }

    nonisolated static func boundary(in headerText: String) -> String? {
        for line in headerText.split(separator: "\r\n") {
            let lower = line.lowercased()
            guard lower.hasPrefix("content-type:"), lower.contains("multipart/form-data") else { continue }
            guard let r = line.range(of: "boundary=", options: .caseInsensitive) else { return nil }
            var value = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") {
                value.removeFirst()
                if let end = value.firstIndex(of: "\"") { value = String(value[..<end]) }
            } else if let semi = value.firstIndex(of: ";") {
                value = String(value[..<semi])
            }
            return value
        }
        return nil
    }

    // MARK: - 字节查找工具

    /// 在 data 的 [from, end) 中查找 pattern，返回其字节区间。
    nonisolated static func range(of pattern: Data, in data: Data, from: Int? = nil) -> Range<Int>? {
        guard !pattern.isEmpty, data.count >= pattern.count else { return nil }
        let start = from ?? data.startIndex
        guard start <= data.endIndex - pattern.count else { return nil }
        let first = pattern[pattern.startIndex]
        var i = start
        let last = data.endIndex - pattern.count
        while i <= last {
            if data[i] == first {
                var matched = true
                var j = 1
                while j < pattern.count {
                    if data[i + j] != pattern[pattern.startIndex + j] { matched = false; break }
                    j += 1
                }
                if matched { return i..<(i + pattern.count) }
            }
            i += 1
        }
        return nil
    }

    /// 清理上传文件名，去掉路径分隔与非法字符，避免目录穿越。
    nonisolated static func sanitize(_ name: String) -> String {
        let base = (name as NSString).lastPathComponent
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = base.components(separatedBy: illegal).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "upload-\(Int(Date().timeIntervalSince1970)).bin" : cleaned
    }

    // MARK: - 本机 IP

    /// 取局域网 IPv4 地址：优先 en0（Wi-Fi），退而求其次取任一非回环 IPv4。
    nonisolated static func localIPAddress() -> String? {
        var primary: String?
        var fallback: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let interface = cur.pointee
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                var addr = interface.ifa_addr.pointee
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(&addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                               &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    if name == "en0" { primary = ip }
                    else if !ip.hasPrefix("127.") && fallback == nil { fallback = ip }
                }
            }
            ptr = interface.ifa_next
        }
        return primary ?? fallback
    }

    // MARK: - 页面 HTML

    /// 上传页：中文 UI，带 multipart/form-data 表单与简单样式。
    nonisolated static func uploadPageHTML() -> String {
        """
        <!DOCTYPE html>
        <html lang=\"zh-CN\">
        <head>
        <meta charset=\"utf-8\">
        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1, maximum-scale=1\">
        <title>Wi-Fi 文件传输</title>
        <style>
          :root { color-scheme: light dark; }
          * { box-sizing: border-box; }
          body { margin: 0; font-family: -apple-system, \"PingFang SC\", system-ui, sans-serif;
                 background: #f2f2f7; color: #1c1c1e; }
          @media (prefers-color-scheme: dark) {
            body { background: #121214; color: #f2f2f7; }
            .card { background: #1c1c1e !important; }
          }
          .wrap { max-width: 520px; margin: 0 auto; padding: 24px 16px 48px; }
          h1 { font-size: 20px; margin: 8px 0 4px; }
          p.sub { color: #8e8e93; font-size: 13px; margin: 0 0 20px; }
          .card { background: #fff; border-radius: 16px; padding: 20px; box-shadow: 0 2px 12px rgba(0,0,0,.06); }
          .drop { border: 2px dashed #0a84ff55; border-radius: 12px; padding: 28px 16px; text-align: center;
                  color: #0a84ff; font-size: 15px; }
          input[type=file] { display: block; width: 100%; margin: 16px 0; font-size: 14px; }
          button { width: 100%; padding: 14px; font-size: 16px; border: none; border-radius: 12px;
                   background: #0a84ff; color: #fff; font-weight: 600; }
          button:active { opacity: .8; }
          .tip { color: #8e8e93; font-size: 12px; margin-top: 16px; line-height: 1.6; }
        </style>
        </head>
        <body>
          <div class=\"wrap\">
            <h1>Wi-Fi 文件传输</h1>
            <p class=\"sub\">选择文件，上传到手机浏览器的下载目录</p>
            <div class=\"card\">
              <form method=\"post\" action=\"/upload\" enctype=\"multipart/form-data\">
                <div class=\"drop\">点击下方选择文件（支持多选）</div>
                <input type=\"file\" name=\"file\" multiple required>
                <button type=\"submit\">上传到手机</button>
              </form>
              <div class=\"tip\">请确保电脑/手机与本机处于同一 Wi-Fi 网络。上传后文件会保存在手机浏览器的「文件 → 下载目录」中。</div>
            </div>
          </div>
        </body>
        </html>
        """
    }

    /// 结果页：成功 / 失败 提示，并提供返回链接。
    nonisolated static func resultPageHTML(success: Bool, message: String) -> String {
        let color = success ? "#34c759" : "#ff3b30"
        let icon = success ? "✓" : "✕"
        let safeMsg = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!DOCTYPE html>
        <html lang=\"zh-CN\">
        <head>
        <meta charset=\"utf-8\">
        <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
        <title>传输结果</title>
        <style>
          :root { color-scheme: light dark; }
          body { margin: 0; font-family: -apple-system, \"PingFang SC\", system-ui, sans-serif;
                 background: #f2f2f7; color: #1c1c1e; display: flex; min-height: 100vh; }
          @media (prefers-color-scheme: dark) { body { background: #121214; color: #f2f2f7; } }
          .box { margin: auto; text-align: center; padding: 32px; }
          .icon { width: 64px; height: 64px; line-height: 64px; border-radius: 50%; margin: 0 auto 16px;
                  font-size: 32px; color: #fff; background: \(color); }
          p { font-size: 15px; color: #8e8e93; }
          a { display: inline-block; margin-top: 20px; color: #0a84ff; text-decoration: none; font-size: 15px; }
        </style>
        </head>
        <body>
          <div class=\"box\">
            <div class=\"icon\">\(icon)</div>
            <p>\(safeMsg)</p>
            <a href=\"/\">继续上传</a>
          </div>
        </body>
        </html>
        """
    }
}
