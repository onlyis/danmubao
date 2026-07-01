import Foundation

extension String {
    /// 把用户输入/相对串规范化为 http(s) URL。
    /// 已是 http(s) 开头则原样使用，否则补 https:// 前缀，再用 URL(string:) 构造；非法返回 nil。
    /// 注意：本方法只负责「补协议 + 构造 URL」，不判断字符串究竟是 URL 还是搜索词，
    /// 该判断仍由调用方自行保留（例如中文关键词/搜索词识别）。
    func asWebURL() -> URL? {
        let normalized = hasPrefix("http") ? self : "https://" + self
        return URL(string: normalized)
    }
}
