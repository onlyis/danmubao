import Foundation

/// BrowserViewModel 搜索职责扩展：
/// 搜索历史的记录/删除、用户自定义搜索引擎的增删、搜索联想词（Bing osjson 接口）的拉取与解析。
extension BrowserViewModel {

    // MARK: - 搜索历史
    func recordSearch(_ q: String) {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        var h = searchHistory
        h.removeAll { $0 == t }
        h.insert(t, at: 0)
        if h.count > 12 { h.removeLast(h.count - 12) }
        searchHistory = h
    }
    func removeSearch(_ q: String) { searchHistory.removeAll { $0 == q } }
    func clearSearchHistory() { searchHistory = [] }

    // MARK: - 自定义搜索引擎
    /// 新增自定义引擎并设为当前。
    func addCustomEngine(name: String, template: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedTpl = template.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedTpl.isEmpty else { return }
        let e = SearchEngine(name: trimmedName, template: trimmedTpl,
                             glyph: String(trimmedName.prefix(1)).uppercased(), colorHex: 0x0A84FF)
        customEngines.removeAll { $0.id == e.id }   // 同名覆盖
        customEngines.append(e)
        searchEngine = e
    }
    func removeCustomEngine(_ e: SearchEngine) {
        customEngines.removeAll { $0.id == e.id }
        if searchEngine.id == e.id { searchEngine = SearchEngine.builtIn[0] }
    }

    // MARK: - 搜索联想词（真实接口）
    /// 拉取联想词：防抖 + 取消旧请求；空 query 立即清空；
    /// 用 Bing osjson 接口（HTTPS，免 Key），解析 JSON 数组第二元素 [词,[建议...]]，回主线程赋值。
    func fetchSuggestions(_ q: String) {
        let keyword = q.trimmingCharacters(in: .whitespaces)
        // 取消上一个未完成的请求，避免乱序覆盖。
        suggestTask?.cancel()
        // 空输入直接清空，无需发请求。
        guard !keyword.isEmpty else {
            searchSuggestions = []
            return
        }
        // 网址/含协议或斜杠的输入不做联想（用户在敲地址）。
        if keyword.contains("://") || keyword.contains(" ") == false && keyword.contains(".") && !keyword.contains("。") {
            // 仅对疑似域名输入跳过联想；普通关键词照常联想。
            if keyword.contains(".") && !keyword.hasSuffix(".") && keyword.asWebURL() != nil && keyword.range(of: "[\\u4e00-\\u9fa5]", options: .regularExpression) == nil {
                searchSuggestions = []
                return
            }
        }
        suggestTask = Task { @MainActor [weak self] in
            // 防抖：等待 220ms，期间被取消则不发请求。
            try? await Task.sleep(nanoseconds: 220_000_000)
            if Task.isCancelled { return }
            guard let self else { return }
            let results = await Self.requestBingSuggestions(keyword)
            if Task.isCancelled { return }
            // 回主线程赋值（本类 @MainActor，await 后已在主线程）。
            self.searchSuggestions = results
        }
    }

    /// 调用 Bing osjson 联想接口并解析结果（非主线程网络，纯静态避免捕获 self）。
    /// 返回示例 JSON: ["swift", ["swiftui","swift 教程", ...]]
    private static func requestBingSuggestions(_ keyword: String) async -> [String] {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.bing.com/osjson.aspx?query=\(encoded)") else {
            return []
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            // 解析 [词, [建议...]]：取第二个元素的字符串数组。
            let json = try JSONSerialization.jsonObject(with: data)
            guard let arr = json as? [Any], arr.count >= 2, let list = arr[1] as? [String] else { return [] }
            return Array(list.prefix(8))
        } catch {
            // 网络/解析失败：静默降级为空建议（不抛错以免打断输入体验），但保留结构化上下文供调试。
            #if DEBUG
            NSLog("fetchSuggestions failed keyword=%@ url=%@ error=%@", keyword, url.absoluteString, String(describing: error))
            #endif
            return []
        }
    }
}
